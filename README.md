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

In two different client terminal windows boot the server and then the client:

```
$ cd server
$ puma
```

```
$ ruby client/script.rb
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

### Rate Reduction Logic - remainging versus sleep value

This is the hardest part. We want a value that is proportional to the number of remaining requests. If there are a lot of remaining requests then we want to remove a lot of sleep time, when there are fewer requests remove less sleep time.

We also have another problem which is that in the fast/slow client problem - say one client is sleeping for 4 seconds (fast) and another is sleeping for 20 seconds (slow). The rate
decrement code will only be called for the slow client one fifth as often as the fast client. That means that the fast client continues to decrement faster and faster while the slow client...keeps on being slow.

Ideally to counter this we would also make the reduction value based off of the sleep time. Ideally each time the 20 second time fires it would decrement by 5x as much as the 4 second client.

There are other approaches but this is one. It unfortunately involves magic values and would be ideal if we had some logic around them.

### Rate Reduction Logic - Different method?

One potential method of adjusting the reduction logic could be to look at the delta of the "remaining" count before and after a request.

Theoretically if there are 100 requests remaining in the ideal system we would expect there to be 100 requests remaing after the client has slept and then made a request. Since we don't want to get stuck on a specific (possibly high) value we could aim for one less, say 99 requests remaining.

The idea here is that if the value is falling we don't want to decrement. If the value is rising then we want to decrement, presumably more based off of how much the count was before so a gain of 100 request would decrement more than a gain of 10 requests. How much should we decrement then? I've not really explored this and i'm sure there are major hurdles such as smoothing and magic numbers etc. Wanted to list it as an idea though incase someone thinks they have an algorithm that might fit.

Initially I was thinking of this kind of like a PID controller, but i'm not sure that's the best mental model for the problem space.
