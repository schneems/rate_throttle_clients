# Rate Limit GCRA Client Demo

## What

The Heroku rate limit algorithm follows [Generic Cell Rate Algorithm](https://brandur.org/rate-limiting). Basically, the idea is that you start with a bucket of requests, 4,500. When you make an API request, then the number goes down. The bucket is also refilled at a rate of 4,500 an hour. Rather than waiting for the end of the hour and adding 4,500 to your limit, the algorithm continuously updates the value throughout the hour. This encourages clients to spread out their requests rather than wait for a fixed time period and then assault the API server.

One downside here is that if you're writing a client, to effectively add rate limiting code, you need to have complete information about your system i.e. how many API clients do you own that are using the same API token. In a distributed system this is a non-trivial problem, any attempts to hard code a number would be invalidated as soon as extra capacity is added to your infrastructure, such as adding more dynos to a background worker process.

That's where this demo comes in. It includes a server that implements a crude version of GCRA and a client that can be configured to run multiple processes and threads.

The goal of the client is to throttle itself without complete information (knowing the total number of clients).

The only thing that this client library has to assume is the maximum number of requests available (4,500 in this case).

## How

To accomplish throttling the client will sleep for a period of time before it makes a request. When there is lots of capacity and few clients then the sleep time should be small. When there is little capacity or many clients (imagine a world where there were 4,500 clients then they can all only make 1 request per hour) then it must sleep for a longer time to wait for requests to be refilled.

Originally I tried to "guess" at the amount of clients that were in the system, however I realized this translated directly to a sleep value and would rather not have to bake in assumptions.

- When a request hits a rate limit then double the amount of time it sleeps before making the next request
- When a request is successful subtract from the sleep value.

Instead of a linear reduction, I chose to have the rate of reduction decrease as the number of remaining requests reported by the API is reduced, so if there are 4500 remaining there will be a large reduction, and if there is 1 remaining there will be a tiny reduction. Instead of a sawtooth pattern, this should produce a logarithmic decrease.

## Run

You can boot both the client and the server by executing the main `main.rb`, this will boot the `server/config.ru` with puma and then run the client `client/script.rb`.

```
$ ruby main.rb
```

Observe the clients eat up the capacity and rate limit themsleves:

```
13946#70249664000540: #status=200 #client_guess=7.570666666672482 #remaining=74 #sleep_for=6.1632330591539715
13946#70249664000400: #status=200 #client_guess=7.554222222228037 #remaining=73 #sleep_for=6.097463071915681
13946#70249664000260: #status=200 #client_guess=7.538000000005815 #remaining=72 #sleep_for=6.62650640512892
13946#70249664000680: #status=200 #client_guess=7.522000000005815 #remaining=78 #sleep_for=6.627982984389338
13946#70249664000840: #status=200 #client_guess=7.504666666672482 #remaining=78 #sleep_for=6.312446465633488
13946#70249664000540: #status=200 #client_guess=7.487333333339149 #remaining=77 #sleep_for=6.465234230526173
13946#70249664000260: #status=200 #client_guess=7.4702222222280374 #remaining=76 #sleep_for=6.227334414609264
13946#70249664000400: #status=200 #client_guess=7.453333333339149 #remaining=75 #sleep_for=6.61480005482600
```

You can adjust the number of threads and processes via env vars.

## Notes

### Jitter

Adding jitter seems to be hugely helpful to spreading out requests, without it then all of the sawtooth patterns overlap and it increases the number of concurrent requests that the server must handle.

I played around with different jitter values. I decided making it proportional based on the current sleep value was reasonable. From zero to 1% was not enough jitter, 0 to 10% seems reasonable but it still a magic number.

### Rate limit increase logic

There's a scenario we want to avoid: Imagine you have two clients, one is a "slow" client and sleeps for say 20 seconds, the other is the a "fast" client and is currently only sleeping for 4 seconds.

When the "fast" client decreases it will trigger rate limit logic for all clients. Statistically it should be more likely that the 4 second client is the one to hit the rate limit, but the "slow" client still has a 1 in 5 chance of doubling and when that happens it will be 40 seconds.


#### Rate limit increase logic - Don't double on first 429

One way to mitigate this that i've tried is to not double the first time a rate limit is hit, but instead first see if sleeping for the original time value will succeed and if not, only then doubling it. In that scenario if the 20 second client hit a rate limit then it would first try sleeping for 20 seconds to see if it was no longer rate limited.

This decreases (but does not eliminate) the likelyhood that the slow client will double instead of the fast client.

The downside is it increases the total number of rate limits that the server ends up seeing. In the worst case scenario, the system will sit and hover in and out of this rate limiting zone with none of the clients ever fully hitting the scenario where it increases it's rate limit. Experimentally the system does seem to eventually get itself out of this zone, but it might linger there for awhile. On one test with 25 total threads (5 processes with 5 threads) the ratio of 429 requests ended up being around 2% which seemed okay.


#### Rate limit increase logic - Don't double dip

When a client is hitting a 429 rate limit request it will trigger the multiplication logic. Even though the system uses jitter, typically each process will group it's requests close together, so it's likely that more than one request will be rate limited.

Imagine a process with 5 threads. Thread 1 and 3 might both be rate limited at about the same time. In this scenario you don't want to double the rate, and then turn around and double again.

To avoid this scenario we record the first thread that is being rate limited and only perform the rate increase logic on that thread.

### Rate limit reduction

The goals in rate reduction logic are:

- Minimize the number of 429 responses from the server, if every other request is being rate limited (50%) then that means we're hammering the server and not doing a good job of spreading things out.
- Allow a single client to "eat up" any available capacity. I.e. we don't want a scenario where there is only one client and they're only making one request an hour even though they have the capacity to make 4500
- Have all processes behave equitably over time: If we have one process sleeping for 100 seconds and one process sleeping for 1 second, that's not a very good division of labor. Ideally the 100 seconds should come down and the 1 second should rise. This is extremely hard.

Now you know the goals, what can we do to affect rate limit reduction.

#### Rate limit reduction logic process

The actual logic of the rate limit is discuessed in the sections under this one, but this is a meta section that explains how i've been tuning the logic (even though the actual logic might not exactly match what i've put here).

Here is how I think of the rate reduction logic. Let's start with a magic number:

```
@sleep_for -= 1
```

In this scenario the sleep value would decrease by 1 after every successful request. How do we know this is a good or bad number? We check to see if it meets our goals. In this case the code would result in a lot of 429 responses because each client is reduced too quickly. That means we need a smaller number. Let's try:


```
@sleep_for -= 1.0/2.0
```

Now we're reducing by a second, good or bad? Still bad. Still hitting 429s. In this scenario we know we need a number less than one, but we're dividing by another magic number, is there something more clever we could do? We could figure out the maximum number of requests in an hour and use that, it's still a magic number but at least it represents something to us in terms of requests:

```
@sleep_for -= 1.0/4500.0
```

Now the 429s aren't a huge problem, but the distribution isn't equitable and when there are 4500 requests avaialble it takes a long time to get a high sleep value down to 0.

Now here's the fun part, we have metrics and data coming from the server. We want to ask ourselves when a given metric is high do we want rate reduction to increase or decrease. Based on that we can put it on the numerator or denominator.

We have `ratelimit_remaining` value returned after every request letting us know how many more requests are availabe in the system, when it is high at (4500) then we want to reduce by a lot, when it is low (1) we want to reduce by a little. We can use it in the numerator:

```
@sleep_for -= ratelimit_remaining/4500.0
```

Now we handle the case where we can "eat up" excess capacity at high values. What about equity?

In the scenario where there is a 20 second client and a 4 second client the 4 second client will fire five times more often than the 20 second client. This means that the fast client keeps tending towards zero and causing rate limit events and at every event there is a 1 in 5 chance that our 20 second client doubles to 40, not good. We want both clients to decrease (relative to each other) proportionally. To do that we could use `@sleep_for`. When it is high, we want to decrease by a lot, when it is low we want to sleep for a little:

```
@sleep_for -= (ratelimit_remaining*@sleep_for)/4500.0
```

Which is the same as:

```
@sleep_for -= ratelimit_remaining/(4500.0/sleep_for)
```

Let's say that there are 100 requests left in the queue, our "slow" client (20 seconds) will be decreased by 0.4 seconds, while the "fast" client (4 seconds) will be reduced by 0.08 seconds. This helps with our equity issue, but now in the case where we are sleeping for 20 seconds, our reduction is now happening 20x faster. Basically while the ratio between clients is reasonable, the rate is too fast, we could magic number to decrease it:

```
@sleep_for -= (ratelimit_remaining*@sleep_for)/(4500.0*20)
```

But magic numbers suck and this is hard coded.

Another issue that we have is clients are "flappy", in the case of 40 second slow and 4 second fast, the "fast" client causes way more 429 rate limit events but the "cost" is amortized across both clients. So may be the fast client might have rate limited 50 times but the slow client only rate limited 6 times. We want a client with a lot of rate limits to decrease it's speed to give a chance for the "slow" client to have a meaningful decrease before the next rate limit event is fired. In that case we would add it to the denominator:

```
@sleep_for -= (ratelimit_remaining*@sleep_for)/(4500.0*rate_limit_count)
```

> Note: This has been replaced with a time based approach. The benefit is that the value has a natural reset point and will not grow indefinetly like the rate limit count

Is this perfect? Could we do better? Maybe. At the time of reading this might not even be what we're doing anymore. The idea of this section is to give you insight into how to think about how to make an affect by modifying this number (add to numerator to make it go faster, add to denominator to make it go slower). We can also do things like use polynomials, exponents, more magic numbers, etc. But in general it helps to first set a goal for desired behavior, then determine a metric that correlates to that behavior, and then figure out the best place to use it in the reduction calcualation.

#### Rate Reduction Logic - remainging versus sleep value

This is the hardest part. We want a value that is proportional to the number of remaining requests. If there are a lot of remaining requests then we want to remove a lot of sleep time, when there are fewer requests remove less sleep time.

We also have another problem which is that in the fast/slow client problem - say one client is sleeping for 4 seconds (fast) and another is sleeping for 20 seconds (slow). The rate
decrement code will only be called for the slow client one fifth as often as the fast client. That means that the fast client continues to decrement faster and faster while the slow client...keeps on being slow.

Ideally to counter this we would also make the reduction value based off of the sleep time. Ideally each time the 20 second time fires it would decrement by 5x as much as the 4 second client.

There are other approaches but this is one. It unfortunately involves magic values and would be ideal if we had some logic around them.


#### Rate Reduction Logic - Make flappy clients slower

When dealing with the fast/slow client problem, the slow client might tend to keep going from 4 towards zero only to be increased back up to 4 again and again and again while the slow client is taking forever to come down from a high value.

We can use the time since a rate limit event to be a proxy for flappy-ness. When a client is flappy then we want it to take longer to reduce it's rate so that it gives a chance for other clients who have a higher sleep value to come down before potentially triggering their rate limiting logic.

The goal is that eventually all clients will be proportionally rate limited, however I'm not sure if the current logic will meet that goal.

Right now we're using a variant of exponential decay to generate a time factor.

```ruby
time_factor = 1.0/(1.0 - Math::E ** -(seconds_since_last_multiply/3600.0))
```

When a client was recently rate limited, this value is high:

```ruby
1.0/(1.0 - Math::E ** -(30/3600.0))
# => 120
```

The longer the client runs without rate limiting, the lower the value will be (tending to 1):

```ruby
1.0/(1.0 - Math::E ** -(3600/3600.0))
# => 1.5819767068693265
```

This term is used in the denominator of our rate reduction logic to slow reduction when high and to speed it up when low.

Before this logic was added we would see the flappy behavior where one client might be at 5 or 10x more rate limit events than other clients. With this logic added in there is still variance, but it seems to allow them to average out.

```
10019#70135134458660: #status=200 #remaining=111 #rate_limit_count=14 #sleep_for=13.768209096835815
10019#70135134458820: #status=200 #remaining=111 #rate_limit_count=14 #sleep_for=13.7439508236652
10020#70135134458380: #status=200 #remaining=112 #rate_limit_count=20 #sleep_for=27.21327764412642
10020#70135134458820: #status=200 #remaining=111 #rate_limit_count=20 #sleep_for=27.179412231947065
10022#70135134458240: #status=200 #remaining=111 #rate_limit_count=22 #sleep_for=15.041531519886027
10019#70135134458240: #status=200 #remaining=113 #rate_limit_count=14 #sleep_for=13.7197352912616
10019#70135134458380: #status=200 #remaining=112 #rate_limit_count=14 #sleep_for=13.69512687716775
10019#70135134458520: #status=200 #remaining=112 #rate_limit_count=14 #sleep_for=13.670779984941674
10020#70135134458520: #status=200 #remaining=112 #rate_limit_count=20 #sleep_for=27.145890956861
10022#70135134458660: #status=200 #remaining=111 #rate_limit_count=22 #sleep_for=15.024666772424336
10018#70135134458380: #status=200 #remaining=112 #rate_limit_count=22 #sleep_for=15.439727858037362
10022#70135134458520: #status=200 #remaining=111 #rate_limit_count=22 #sleep_for=15.00782093392192
10020#70135134458660: #status=200 #remaining=112 #rate_limit_count=20 #sleep_for=27.11210940367024
10018#70135134458240: #status=200 #remaining=111 #rate_limit_count=22 #sleep_for=15.422260691167663
10018#70135134458660: #status=200 #remaining=111 #rate_limit_count=22 #sleep_for=15.404969065544233
10018#70135134458820: #status=200 #remaining=110 #rate_limit_count=22 #sleep_for=15.387696827501047
10018#70135134458520: #status=200 #remaining=109 #rate_limit_count=22 #sleep_for=15.3705993865816
10021#70135134458660: #status=200 #remaining=112 #rate_limit_count=23 #sleep_for=41.49060981439041
10019#70135134458660: #status=200 #remaining=111 #rate_limit_count=14 #sleep_for=13.646476376079557
10019#70135134458820: #status=200 #remaining=110 #rate_limit_count=14 #sleep_for=13.62243258436932
10022#70135134458380: #status=200 #remaining=110 #rate_limit_count=22 #sleep_for=14.990993983177825
10022#70135134458820: #status=200 #remaining=109 #rate_limit_count=22 #sleep_for=14.974337323196517
10020#70135134458240: #status=200 #remaining=108 #rate_limit_count=20 #sleep_for=27.078369889745673
10022#70135134458240: #status=200 #remaining=111 #rate_limit_count=22 #sleep_for=14.957850426547745
10019#70135134458240: #status=200 #remaining=113 #rate_limit_count=14 #sleep_for=13.598647384618834
10019#70135134458380: #status=200 #remaining=112 #rate_limit_count=14 #sleep_for=13.574256159944836
10019#70135134458520: #status=200 #remaining=112 #rate_limit_count=14 #sleep_for=13.550124148993824
10022#70135134458660: #status=200 #remaining=112 #rate_limit_count=22 #sleep_for=14.941079503342221
10018#70135134458380: #status=200 #remaining=114 #rate_limit_count=22 #sleep_for=15.353676201398395
10022#70135134458520: #status=200 #remaining=113 #rate_limit_count=22 #sleep_for=14.924176463904097
10018#70135134458240: #status=200 #remaining=114 #rate_limit_count=22 #sleep_for=15.335996210621028
10018#70135134458820: #status=200 #remaining=113 #rate_limit_count=22 #sleep_for=15.318336578620919
10018#70135134458660: #status=200 #remaining=114 #rate_limit_count=22 #sleep_for=15.30085201262714
10018#70135134458520: #status=200 #remaining=113 #rate_limit_count=22 #sleep_for=15.283232849703507
10019#70135134458660: #status=200 #remaining=113 #rate_limit_count=14 #sleep_for=13.526035039395612
10019#70135134458820: #status=200 #remaining=113 #rate_limit_count=14 #sleep_for=13.501774055912252
10020#70135134458380: #status=200 #remaining=113 #rate_limit_count=20 #sleep_for=27.04587584587798
10020#70135134458820: #status=200 #remaining=112 #rate_limit_count=20 #sleep_for=27.01191824620482
10022#70135134458820: #status=200 #remaining=111 #rate_limit_count=22 #sleep_for=14.907141797839236
10022#70135134458380: #status=200 #remaining=110 #rate_limit_count=22 #sleep_for=14.890427729762871
```


### Scratch/What-if

One potential method of adjusting the reduction logic could be to look at the delta of the "remaining" count before and after a request.

Theoretically if there are 100 requests remaining in the ideal system we would expect there to be 100 requests remaing after the client has slept and then made a request. Since we don't want to get stuck on a specific (possibly high) value we could aim for one less, say 99 requests remaining.

The idea here is that if the value is falling we don't want to decrement. If the value is rising then we want to decrement, presumably more based off of how much the count was before so a gain of 100 request would decrement more than a gain of 10 requests. How much should we decrement then? I've not really explored this and i'm sure there are major hurdles such as smoothing and magic numbers etc. Wanted to list it as an idea though incase someone thinks they have an algorithm that might fit.

Initially I was thinking of this kind of like a PID controller, but i'm not sure that's the best mental model for the problem space.


## How the F to test this?

This behavior is very hard to test. Why? While the rules are fairly simple (around 100 ish lines of Ruby code for the rate limiter) they have [emergent bevhavior]() that comes from these rules. To make things harder, to really test this emergent behavior, we must `sleep()` which causes code to run for extended periods. To make hard things harder, the code involves syncronizing multiple async clients and requires a server to fully test.

Ideally we would test the "behavior" of the system and not the logic but without the ability to simulate running through an entire day in a few seconds, I don't know how we could do that.

I tried timecop, but it does not affect sleep:

```
require 'timecop'
Timecop.scale(100)
sleep(100) # would expect this to only sleep for 1 second due to timecop but sleeps for 100
```

Behavior I want to test;

- One client consumes all available requests "quickly"
- Fast/Slow client allows "slow" client to come down
- Flappy clients are encouraged to be not flappy
- When fast/slow clients both hit a rate limit the "fast" client is more likely to be chosen.
- Percent/rate of rate limits received by the server is within some reasonable bounds (initial simulations of this behavior look like rate limits account for 2-3% of requests)


Can do:

- Check when time since multiply changes the decrease amount changes
- When remaining changes decrease amount changes
-