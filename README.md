# Rate Limit GCRA Client Demo

## What is Rate Limiting (server side)?

The Heroku rate limit algorithm follows [Generic Cell Rate Algorithm](https://brandur.org/rate-limiting). Basically, the idea is that you start with a bucket of requests, 4,500. When you make an API request, then the number goes down. The bucket is also refilled at a rate of 4,500 an hour. Rather than waiting for the end of the hour and adding 4,500 to your limit, the algorithm continuously updates the value throughout the hour. This encourages clients to spread out their requests rather than wait for a fixed time period and then assault the API server.

## What is rate throttling (client side)?

While the server will reject requests if they are over the limit, the client can use this information to behave differently. For example they could "smooth out" their requests over time. When they detect a client is rate limited, they can retry the request after sleeping for some time. Without rate throttling these requests would fail and everyone (the client and server) would have a bad time.

## What MUST an effective rate throttle algorithm do?

- Works on distributed systems: It is very easy to rate throttle one client on one machine. When it hits a rate throttle event, it sleeps for the specified amount of time for another request to be available and retries. It's slightly more difficult with multiple clients in the same process. When the problem spans multiple processes on multiple machines, it becomes a distributed coordination problem. The algorithm needs to function without requiring expensive or complicated coordination. The only information it has about the overall system comes from headers served from the server or from it's own prior experience.

## What makes a good rate throttle algorithm?

- Equitable distribution of requests across the system: If there are two clients and one client is throttling by sleeping for 100 seconds and the other is throttling for 1 second, the distribution of requests are not equitable. Ideally over time each client might go up or down, but both would see a median of 50 seconds of sleep time. Why? If processes in a system have a high variance, one process is starved for API resources. It then becomes difficult to balance or optimize otherworkloads. When a client is stuck waiting on the API, ideally it can perform other operations (for example in other threads). If one process is using 100% of CPU and slamming the API and other is using 1% of CPU and barely touching the API, it is difficult to balance the workloads.
- Minimize retry ratio: For example if every 50 successful requests, the client hits a rate limited request the ratio of retries is 1/50 or 2%. Why minimize this value? It takes CPU and Network resources to make requests that fail, if the client is making requests that are being limited, it's using resources that could be better spent somewhere else. The server also benefits as it spends less time dealing with rate limiting.
- Minimize sleep/wait time: Retry ratio can be improved artificially by choosing high sleep times. In the real world consumers don't want to wait longer than absolutely necessarry. While a client might be able to "work steal" while it is sleeping/waiting, there's not guarantee that's the case. Essentially assume that any amount of time spent sleeping over the minimum amount of time required is wasted. This value is calculateable, but that calculation requires complete information of the distributed system.
  - At high workload it should be able to consume all available requests: If a server allows 100,000 requests in a day then a client should be capable of making 100,000 requests. If the rate limiting algorithm only allows it to make 100 requests it would have low retry ratio but high wait time.
  - Handle a change in work load to either slow down or speed up rate throttling: If the workload is light, then clients should not wait/sleep much. If workload is heavy, then clients should sleep/wait enough. The algorithm should adjust to a changing workload as quickly as possible.

 ## What is this repo?

The purpose of this repo is to explore how better rate throttling algorighms can be written and to demonstrate and "prove" the "quality" of what can be considered a "good" rate throttling algorithm.

This repo includes a "fake" server that implements a rudimentary version of GCRA rate limiting. It also features several rate throttling algorithms that can be used to make requests against that server. Simulations can be run with this repo. Since there is a lot of waiting involved, (sleeping and rate limiting) time can be "scaled" to go faster. By setting the `TIME_SCALE` env var. A value of 10 will make an hour long simulation take 6 minutes. Exceeding a value of 10 isn't recommended.

While running, several critical values are logged for the purposes of comparing rate throttling algorithm fitness.

- retry_ratio: Represents the percentage (a number from 0 to 1) of requests that needed to be retried. Should be minimized (Minimize retry ratio).
- max_sleep_val: Represents the maximum value that a given client had to sleep. Should be minimized (minimize sleep/wait time).
- request_count: Represents the total number of requests (success + retry) that a given client should make. Variance of request count between clients should be minimized (equitable distribution).

In addition to these cumulative metrics, the amount of time a given client is sleeping for is sampled in order to produce graphs of the clients as they're running over time.

Here's an example of this library throttling 5 processes each with 5 threads over the course of 5 hours. The y axis represents the amount of time a client is throttled by before a request, the x axis represents time.

![](https://www.dropbox.com/s/ppptbgk215ihdzy/Screenshot%202020-04-07%2021.22.41.png?raw=1)

## How to use this repo

There are [several rate throttling clients](https://github.com/schneems/rate-limit-gcra-client-demo/tree/master/client), a [fake server](https://github.com/schneems/rate-limit-gcra-client-demo/blob/master/lib/rate_limit_fake_server.rb) and a [class to drive a smulation](https://github.com/schneems/rate-limit-gcra-client-demo/blob/master/lib/rate_throttle_demo.rb).

There are two different ways to drive a simulation. There is a [main.rb](https://github.com/schneems/rate-limit-gcra-client-demo/blob/master/main.rb) that can be edited to specify a specific client and run a simulation:

```
$ TIME_SCALE=10 ruby main.rb
60930#70203979671860: status=429 remaining=0 retry_count=1 request_count=1 max_sleep_val=0.00
60930#70203979670460: status=429 remaining=0 retry_count=1 request_count=1 max_sleep_val=0.82
60929#70203979671120: status=429 remaining=0 retry_count=1 request_count=1 max_sleep_val=0.00
60930#70203979670780: status=429 remaining=0 retry_count=1 request_count=1 max_sleep_val=0.85
# ...
```

This will drive the client for a period of time specified in `main.rb` and stream logs. It also periodically writes values to disk so that if you cancel the run via `CTRL+C` it will output the results:

```
# ...
60930#70203979670780: status=429 remaining=0 retry_count=1 request_count=1 max_sleep_val=0.85

CTRL+C
## Raw ExponentialIncreaseSleepAndRemainingDecrease results

max_sleep_val: [854.89, 837.72, 854.89, 854.89, 837.72, 837.72, 854.89, 837.72, 854.89, 837.72]
retry_ratio: [0.62, 0.62, 0.62, 0.64, 0.61, 0.68, 0.62, 0.62, 0.67, 0.60]
request_count: [700.00, 866.00, 614.00, 120.00, 520.00, 101.00, 1242.00, 684.00, 93.00, 935.00]

Traceback (most recent call last):
  7: from main.rb:19:in `<main>'
  6: from /Users/rschneeman/Documents/projects/ratelimit-demo/lib/rate_throttle_demo.rb:78:in `call'
  5: from /Users/rschneeman/Documents/projects/ratelimit-demo/lib/rate_throttle_demo.rb:78:in `new'
  4: from /Users/rschneeman/.gem/ruby/2.6.4/gems/wait_for_it-0.2.1/lib/wait_for_it.rb:96:in `initialize'
  3: from /Users/rschneeman/Documents/projects/ratelimit-demo/lib/rate_throttle_demo.rb:85:in `block in call'
  2: from /Users/rschneeman/Documents/projects/ratelimit-demo/lib/rate_throttle_demo.rb:85:in `map'
  1: from /Users/rschneeman/Documents/projects/ratelimit-demo/lib/rate_throttle_demo.rb:85:in `block (2 levels) in call'
/Users/rschneeman/Documents/projects/ratelimit-demo/lib/rate_throttle_demo.rb:85:in `wait': Interrupt
```

Once you've run a simulation you can plot the latest values using `chart.rb`

```
$ TIME_SCALE=10 ruby chart.rb
```

<!-- Ruby 2.6.4 -->

To plot a different run, specify the directory manually:

```
$ TIME_SCALE=10 ruby chart.rb specific/directory/here/
```

In addition to driving things manually there are several rake tasks:

```
$ rake bench:workload
```

This task simulates a client that starts with a prior sleep value but the server has a lot of remaining requests, it then outputs how long it takes for the client to consume all the remaining requests. This is a metric for the "Handle a change in work load" criteria.

```
$ rake bench
```

This task runs multiple clients quietly for 30 (simulated) minutes and then outputs their results. You can edit the Rakefile manually to specify the clients you want.

## How to write a Rate throttling algorithm

One method of writing a retry algorithm is to write the simplest thing that could work, then observe what could be better about it and iterate until better values are achieved. What follows are a list of clients, some are theoretical and some are implemented in the [clients directory](https://github.com/schneems/rate-limit-gcra-client-demo/tree/master/client).

### Retry Only

A primitive rate throttling algorithm is nothing more than a retry algorithm. When a request comes back as rate limited (429 response) then it can be retried.

- Pros: Super simple
- Cons: Extremely high retry ratio. Is essential a DDoS to the server and cause your account to get suspended.

### Retry with backoff

A step up from "retry only" is to make requests, then when a 429 is hit, sleep before the next request is made.

- Pros: Still very simple
- Cons: Difficult to find the "right" value to sleep. This violates several requirements of what a rate throttling algorithm must be able to do.

### Retry with exponential backoff

Instead of hard-coding a sleep value, clients can instead sleep for progressively higher values, some multiplier of the value that was previously tried. A common value is 2x the prior sleep request, and a good place to start sleeping is the minimum amount of time to sleep for 1 request to become available via the server. As soon as a successful request is made, stop sleeping until the next 429 is hit

This algorithm is implemented in https://github.com/schneems/rate-limit-gcra-client-demo/blob/master/client/exponential_backoff_throttle.rb so we actually have numbers. This is from a 30 minute run (multiplier=2):

```
max_sleep_val: [854.89, 837.72, 854.89, 854.89, 837.72, 837.72, 854.89, 837.72, 854.89, 837.72]
retry_ratio: [0.62, 0.62, 0.62, 0.64, 0.61, 0.68, 0.62, 0.62, 0.67, 0.60]
request_count: [700.00, 866.00, 614.00, 120.00, 520.00, 101.00, 1242.00, 684.00, 93.00, 935.00]
```

This means that the maximum time spent sleeping over a 30 minute period was around 854 seconds (14 minutes), the retry ratio was around 60% (so only about 40% of requests were successful. And the distribution of request counts is not very even with the lowest at 93 requests and the highest at 935, the standard deviation is 387.

Here is a chart of this algorithm running:

![chart](https://user-images.githubusercontent.com/59744/78417124-ae99b380-75f4-11ea-9b13-d13508ce6379.png)

- Pros:
  - Relatively simple,
  - Does not DDoS the server
  - Does not violate rate throttle requirements
  - A valid rudimentary solution
- Cons:
  - A very high sleep value
  - A very high retry ratio
  - A high request variance

Over time it actually gets worse, here's an example of a 120 minute run (multiplier=2):

```
max_sleep_val: [3370.67, 1800.49, 3370.67, 1800.49, 1800.49, 3370.67, 3370.67, 1800.49, 1800.49, 3370.67]
retry_ratio: [0.60, 0.61, 0.60, 0.60, 0.62, 0.59, 0.60, 0.60, 0.60, 0.66]
request_count: [1176.00, 2318.00, 1581.00, 3472.00, 1975.00, 2276.00, 3611.00, 1988.00, 3659.00, 602.00]
```

The maximum time spent sleeping is nearly an hour (3600 seconds) which is a LONG time to sleep. The stdev is now 1043, which is 3 times higher. To write a better algorithm, let's explore why this behavior exists.

If you look at the graph you see that some clients sleep time keeps going up and up, while other client's sleep time hover at a low value for a long duration. Why is that? Since there is no sleeping time when requests are comming back as a success the server is getting hammered. This algorithm does reduce the number of failed requests, but not by a whole lot (retry ratio is still 60%). So when a request is made, there's a 60% chance that it will be rate limited. This is true over the distributed system. For clients that have a small value, they have a 60% chance of doubling a small value, while clients sleeping for a large value have a 60% chance of doubling that large value. To minimize this chance of "runaway" high sleep time behavior, the system needs to reduce the retry ratio (reduces chances of retrying a large sleep value) and make the request count more equitable (if all clients are retrying the same amount, there's less chance that one of them will be an outlier with a high sleep value).

We can adjust the multiplier for the exponential backoff from 2 to another value such as 1.2 or 3. When we do that what happens to the values?

We will guess about the results and then try them experimentally. First let's try a multiplier of 1.2. What do we predict will happen?

- Lowering the multiplier (to 1.2) Guess:
  - Retry ratio is increased since it takes more retries to get to a large value
  - Max sleep value is decreased since sleep time increases are more granular
  - Request count variance, I'm not sure, probably about the same

Here's experimental results from a 30 minute run (multiplier=1.2):

```
max_sleep_val: [33.35, 134.88, 134.88, 33.35, 134.88, 33.35, 33.35, 134.88, 33.35, 134.88]
retry_ratio: [0.80, 0.81, 0.80, 0.80, 0.82, 0.81, 0.80, 0.79, 0.80, 0.79]
request_count: [1257.00, 738.00, 1016.00, 1335.00, 598.00, 1135.00, 1350.00, 1068.00, 1233.00, 1465.00]
```

Sleep values are WAY down. Which is good. Retry ratio is up, which is bad. This means that we're only succeeding for 20% of the requests that we make. Variance is a lower with a stdev of 275 requests (down from 387).

- Increasing the multiplier (to 3) Guess:
  - Max sleep value goes up
  - Retry ratio goes down
  - Request count variance is about the same, maybe a little higher

Here's the experimental results for a 30 minute run (multiplier=3):

```
max_sleep_val: [1847.50, 641.35, 1847.50, 641.35, 641.35, 1847.50, 1847.50, 641.35, 641.35, 1847.50]
retry_ratio: [0.70, 0.53, 0.52, 0.53, 0.51, 0.56, 0.64, 0.55, 0.53, 0.57]
request_count: [43.00, 508.00, 838.00, 1080.00, 551.00, 283.00, 77.00, 705.00, 372.00, 416.00]
```

Max sleep value is up, retry ratio went down (previously was 60%, now averaging 56%, so not a huge difference). Stdev for request count is 325.

It looks like our intuition about sleep value and retry ratio is roughly correct. Unfortunately tuning one value to be better, makes the other worse. If we want both sleep value and retry ratio to be better then, we'll have to adopt a new approach. Intuition about request variation is mixed. They're in the same ballpark though.

If we want to make this better we could use an algorithm with a low retry rate and find some way to bring down the sleep values, or a low sleep value and find a way to bring down the retry rate. The 1.2 multiplier had a fairly low sleep value, but a higher retry ratio. Let's start there.

To decrease retry ratio, we'll have to slow down request rate. One way to do this is via sleeping before all requests, not just rate-limited-requests.

## Exponential sleep increase, gradual decrease

Use the same exponential backoff algorithm as before, but now after we make a successful request instead of not sleeping at all, we preserve the sleep value and before the next request. If it's successful then we decrease the amount we have to sleep on every successful request.

This is implemented in: (https://github.com/schneems/rate-limit-gcra-client-demo/blob/master/client/exponential_increase_gradual_decrease.rb)

Like before, when the client is rate limitied it has an exponential increase, but now, after a successful request it will continue to sleep the same amount, but slightly less. Since before tuning the exponential multiplier affected the system a large amount, the amount decreased will have a large impact:

We can start with a small value. In a 4500 GCRA system, when it runs out of requests another will be added in  1 (hour) / (4500 requests per hour) * 3600 (seconds/hour) is 0.8 seconds for the next request to become available. For a 30 minute run (multiplier=1.2 decrease=0.8)

```
max_sleep_val: [184.55, 208.81, 208.81, 184.55, 208.81, 184.55, 184.55, 208.81, 184.55, 208.81]
retry_ratio: [0.51, 0.56, 0.45, 0.51, 0.58, 0.67, 0.45, 0.45, 0.43, 0.55]
request_count: [43.00, 39.00, 53.00, 41.00, 38.00, 33.00, 3720.00, 51.00, 68.00, 49.00]
```

Max sleep value went up, retry ratio went down and variance is off the charts (stdev=1161). We still need to decrease all these values. We can try using a different decrease rate.

Here's the chart:

![](https://www.dropbox.com/s/elb9z2sbxegr71k/Screenshot%202020-04-07%2011.37.02.png?raw=1)

You can see that this does have some desired properties. You can see some clients beginning to come down, but you also see one client essentially riding the floor and not sleeping at all. That's where the high variance comes from.

Somehow we need to make the clients that have low sleep time decrease very slowly, and the clients with high sleep time decrease faster. We can accomplish this via decreasing and taking sleep time into account:

```
decrease_value = (sleep_time) / some_value
```

Where `some_value` is tunable.

### Exponential increase proportional decrease

When a rate limit is triggered, exponentially increase, when successful request reduce sleep value by an amount proportional to sleep value. Implemented in https://github.com/schneems/rate-limit-gcra-client-demo/blob/master/client/exponential_increase_proportional_decrease.rb

For a 30 minute run (multiplier=1.2 decrease_divisor=4500)

```
max_sleep_val: [17.27, 17.20, 17.20, 17.27, 17.27, 17.27, 17.20, 17.20, 17.20, 17.27]
retry_ratio: [0.03, 0.06, 0.05, 0.07, 0.02, 0.01, 0.03, 0.03, 0.03, 0.04]
request_count: [244.00, 141.00, 172.00, 115.00, 336.00, 418.00, 193.00, 202.00, 186.00, 230.00
```

Sleep value is down, retry ratio is orders of magnituded better. Request variance is 91 wich is the best we've seen yet. Here's the chart:

![](https://www.dropbox.com/s/rq0gpqtglzubrto/Screenshot%202020-04-07%2011.54.06.png?raw=1)

What is especially interesting here to me is that clients that are "high" can move to low values and clients that are low can move to high values.

The value 4500 is a magic, tunable number. If we increase it I would expect retry ratio to go down, if I decrease it I would expect retry ratio to go up.

For a longer run, for a 120 minute run (multiplier=1.2 decrease_divisor=4500)

```
max_sleep_val: [19.68, 13.55, 13.55, 19.68, 13.55, 19.68, 19.68, 13.55, 19.68, 13.55]
retry_ratio: [0.01, 0.00, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.00]
request_count: [882.00, 1567.00, 935.00, 727.00, 737.00, 642.00, 736.00, 1023.00, 747.00, 1075.00]
```

![](https://www.dropbox.com/s/bjepltsv4wwzujd/Screenshot%202020-04-07%2013.03.43.png?raw=1)

This looks outstanding. The optimal calculated sleep value would be 8 seconds (0.8 seconds per client * 10 clients).

Now the question is: What (if anything is bad about this client)? In this simulation the workload is steady. That is, requests are spread out relatively even throughout the entire simulation. Instead, what if there was a flury of activity, say from a bunch of jobs being enqueued, and then there's a period of domancy, and then a period of activity.

We can test by seeing how long it would take to consumer all requests, given an initial sleep value that is higher than optimal, say 10 seconds. In that case decrease per successfull request will be (10/4500) which is 0.002. With that decrease rate, it will take 500 requests to decrease by 1 second and a thousand requests to decrease by 2 seconds (though longer since it's proportional). At a rate of one request every 10 seconds it would take 83 minutes (over an hour) to decrease the value by only 1 second.

It will eventually find a steady state, but it will take a LONG time.

Here is a chart:

![](https://www.dropbox.com/s/ok5owh6d7za5x3p/Screenshot%202020-04-07%2016.41.22.png?raw=1)

It takes nearly 7 hours to fully consume all available requests and find a new steady state. Not good.

Pros:
- All metrics are good

Cons:
- Cannot handle a change in work load well.


As a comparison I added a test to see how long a client set for an initial sleep of 10 seconds (if it retains sleep value), how long it would take to clear 4500 requests. The ExponentialBackoff client which does not preserve sleep takes:

```
Time to clear workload: 321.75476813316345 seconds
```

This is roughly 5 minutes. 7 hours is not acceptable for the proportional client. Instead we need a way to decrease faster when there's lots of remaining requests, and slower when there are fewer.

### Exponential increase proportional decrease based on sleep value and remaining requests

Same exponential increase behavior, now we add the rate_limit_remainging value to our decrease (implemented in https://github.com/schneems/rate-limit-gcra-client-demo/blob/master/client/exponential_increase_sleep_and_remaining_decrease.rb):

```
decrease_value = (sleep_time * rate_limit_remaining) / some_value
```

For a 30 minute run (multiplier=1.2, decrease_divisor=4500, with rate limit)

```
max_sleep_val: [13.14, 17.18, 17.18, 17.18, 13.14, 17.18, 13.14, 17.18, 13.14, 13.14]
retry_ratio: [0.02, 0.03, 0.04, 0.05, 0.04, 0.06, 0.07, 0.11, 0.05, 0.02]
request_count: [217.00, 155.00, 143.00, 123.00, 162.00, 117.00, 105.00, 73.00, 116.00, 218.00]

Time to clear workload: 314.27748004486085 seconds
```

![](https://www.dropbox.com/s/5h6j2dnvddj5bq1/Screenshot%202020-04-07%2020.30.50.png?raw=1)

The retry ratio is higher, but still orders of magnitude better than regular exponential. The time to clear 4500 requests is pretty low (5.2 minutes), and the variance is within reason with a stdev of 46.8.


For a 180 minute run (multiplier=1.2, decrease_divisor=4500, with rate limit)

```
max_sleep_val: [25.11, 35.71, 35.71, 25.11, 35.71, 25.11, 35.71, 25.11, 25.11, 35.71]
retry_ratio: [0.02, 0.01, 0.01, 0.01, 0.02, 0.01, 0.01, 0.01, 0.02, 0.01]
request_count: [754.00, 2034.00, 1331.00, 1221.00, 1110.00, 1360.00, 2213.00, 1027.00, 996.00, 2170.00]
```

Screenshot of a 5 hour run:

![](https://www.dropbox.com/s/ppptbgk215ihdzy/Screenshot%202020-04-07%2021.22.41.png?raw=1)

720 minute run:

```
max_sleep_val: [33.55, 36.63, 36.63, 33.55, 36.63, 33.55, 36.63, 33.55, 36.63, 33.55]
retry_ratio: [0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01]
request_count: [7825.00, 4059.00, 5336.00, 8213.00, 3949.00, 5527.00, 5594.00, 7424.00, 4011.00, 7121.00]
```

![](https://www.dropbox.com/s/xu7z6wxj3x2h80j/Screenshot%202020-04-07%2022.07.01.png?raw=1)

## Winner

The "Exponential increase proportional decrease based on sleep value and remaining requests" exhibits excelent behavior in all of our criteria. If we wanted to improve it, the next step would be to make another rate throttling client, and benchmark it against this one.

## Happy accidents - A race condition

You might have noticed in the charts that there are large periods of increases, which make sense given we're multiplying exponentially when a rate limit is triggered. You might have also seen a line where a value suddenly drops, like this one (look at white):

![](https://www.dropbox.com/s/lvjv89kfsgadht5/Screenshot%202020-04-07%2021.53.25.png?raw=1)

What's going on there? When I coded the "Exponential sleep increase, gradual decrease" I wanted to make it as simple as possible. I wanted each thread to be independent and not use any mutexes for updating values. I knew this would cause a race condition, but I thought that was fine (it is fine, but the behavior is still surprising enough to explain). The logic flow looks something like this:

```
local_sleep_value = @shared_sleep_value

make_request
sleep(local_sleep_value)
update(local_sleep_value)

@shared_sleep_value = local_sleep_value
```

Since we're calling it in a loop, it ends up looking kind of like this:

```
local_sleep_value = @shared_sleep_value

#...

@shared_sleep_value = local_sleep_value # <====
local_sleep_value = @shared_sleep_value # <====

#...

@shared_sleep_value = local_sleep_value
```

What this ends up meaning is that the `@shared_sleep_value` has a very small time window where it can be over-written by another thread for it to actually affect another thread. Here's some logs:

```
7397#70117824783640: Setting sleep_for: 15.75507386941004
7397#70117824783640: Getting sleep_for: 15.75507386941004
7397#70117824782680: # Make request
7397#70117824782680: Setting sleep_for: 9.444155235725503
7397#70117824782680: Getting sleep_for: 9.444155235725503
7397#70117824782360: # Make request
7397#70117824782360: Setting sleep_for: 9.44043609284105
7397#70117824782360: Getting sleep_for: 9.44043609284105
7397#70117828787280: # Make request
7397#70117828787280: Setting sleep_for: 9.442902221532192
7397#70117828787280: Getting sleep_for: 9.442902221532192
7397#70117828787700: # Make request
7397#70117828787700: Setting sleep_for: 9.444155235725503
7397#70117828787700: Getting sleep_for: 9.444155235725503
7397#70117828787700: Getting sleep_for: 9.444155235725503
7397#70117824782680: # Make request
7397#70117824782680: Setting sleep_for: 9.442056534562008
7397#70117824782680: Getting sleep_for: 9.442056534562008
7397#70117824782360: # Make request
7397#70117824782360: Setting sleep_for: 9.438338218153753
7397#70117824782360: Getting sleep_for: 9.438338218153753
7397#70117828787280: # Make request
7397#70117828787280: Setting sleep_for: 9.440803798816296
7397#70117828787280: Getting sleep_for: 9.440803798816296
7397#70117824783640: # Make request
7397#70117824783640: Setting sleep_for: 15.751572741883505 # <== Swap happens here
7397#70117828787700: # Make request
7397#70117828787700: Setting sleep_for: 9.442056534562008
7397#70117828787700: Getting sleep_for: 9.442056534562008 # <== Same process, different value
```

Race conditions are bad, unpredictability is bad. Why is this a "happy" accident? In general we want some controlled randomness. We also want to not leave really high values high for too long, and this process is more likely to accidentally reduce a value than to increase it. Why? Values that are low indicate threads that are firing rapidly, the more often a thread fires, the more often it will set this value. So while we do see random jump ups, the jump down is more likely.

We could fix this by storing this data as a thread local. But I like this behavior. In general we don't want a process or a thread "stuck" in one position for too long and this race condition behavior seems to reduce variance.

It's worth noting that this behavior only happens if you're running clients in threads. If you're only executing one client per process (which is likely the case for most people) there will be no race condition. If you instantiate one client per thread, there will be no race condition.


