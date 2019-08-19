# Rate Limit Demo

## What

The Heroku rate limit algorithm follows [Generic Cell Rate Algorithm](https://brandur.org/rate-limiting). Basically, the idea is that you start with a bucket of requests, 4,500. When you make an API request, then the number goes down. The bucket is also refilled at a rate of 4,500 an hour. Rather than waiting for the end of the hour and adding 4,500 to your limit, the algorithm continuously updates the value throughout the hour. This encourages clients to spread out their requests rather than wait for a fixed time period and then assault the API server.

One downside here is that if you're writing a client, to effectively add rate limiting code, you need to have complete information about your system i.e. how many API clients do you own that are using the same API token. In a distributed system this is a non-trivial problem, any attempts to hard code a number would be invalidated as soon as extra capacity is added to your infrastructure, such as adding more dynos to a background worker process.

That's where this demo comes in. It includes a server that implements a crude version of GCRA and a client that can be configured to run multiple processes and threads.

The goal of the client is to throttle itself without complete information (knowing the total number of clients).

## How

To accomplish throttling the client will sleep for a period of time before it makes a request. When there is lots of capacity and few clients then the sleep time should be small. When there is little capacity or many clients (imagine a world where there were 4,500 clients then they can all only make 1 request per hour) then it must sleep for a longer time to wait for requests to be refilled.

This client uses a similar algorithm to TCP congestion control, though backwards. The rate at which it sleeps is decreased linearly over time as requests are successful, then when a rate limit is hit the value is increased multiplicitively

The idea is that we want to minimize the number of rejected requests from the server (since rejecting requests is not completely free) but we also don't want to leave excess capacity on the floor by sleeping for too long.




## Run

In two different client terminal windows boot the server and then the client:

```
$ cd server
$ puma
```

```
$ ruby client/script.rb
```

## Questions/Issues

The rate at which the increase and decrease happens can be tuned as well as the starting sleep rate. Ideally if you boot a single client that only needs to make a handful of requests every hour, you don't want it to take 24 hours to realize it doesn't need to sleep at all. Conversely if you boot many processes with say 500 clients and making requests constantly, you don't want them to increase sleep time so fast that it cannot reasonably come back down, you also dont want it to be too "flappy" by decreasing the sleep time too fast which would trigger the increase logic.

At the time of this writing the rates are:

- When a successful request happens decrease by `\<number of requests left\>/4500`
