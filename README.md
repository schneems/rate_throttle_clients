# Rate Limit GCRA Client Demo

## What

The Heroku rate limit algorithm follows [Generic Cell Rate Algorithm](https://brandur.org/rate-limiting). Basically, the idea is that you start with a bucket of requests, 4,500. When you make an API request, then the number goes down. The bucket is also refilled at a rate of 4,500 an hour. Rather than waiting for the end of the hour and adding 4,500 to your limit, the algorithm continuously updates the value throughout the hour. This encourages clients to spread out their requests rather than wait for a fixed time period and then assault the API server.

One downside here is that if you're writing a client, to effectively add rate limiting code, you need to have complete information about your system i.e. how many API clients do you own that are using the same API token. In a distributed system this is a non-trivial problem, any attempts to hard code a number would be invalidated as soon as extra capacity is added to your infrastructure, such as adding more dynos to a background worker process.

That's where this demo comes in. It includes a server that implements a crude version of GCRA and a client that can be configured to run multiple processes and threads.

The goal of the client is to throttle itself without complete information (knowing the total number of clients).

The only thing that this client library has to assume is the maximum number of requests available (4,500 in this case).

## How

To accomplish throttling the client will sleep for a period of time before it makes a request. When there is lots of capacity and few clients then the sleep time should be small. When there is little capacity or many clients (imagine a world where there were 4,500 clients then they can all only make 1 request per hour) then it must sleep for a longer time to wait for requests to be refilled.

If we knew exactly how many clients there were then we could use that information to determine the perfect amount of time to sleep before making a request. Instead we can try to guess how many clients there are and sleep for that same amount of time and adjust this value when a rate limit event occurs or when a request is successful:

- When a request hits a rate limit then double the number of clients it assumes exist
- When a request is successful subtract from the number of clients it assumes exist

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

Adding jitter seems to be hugely helpful to spreading out requests, without it then all of the sawtooth patterns overlap and it increases the number of concurrent requests that the server must handle.

I played around with different jitter values. I decided making it proportional based on the current sleep value was reasonable. From zero to 1% was not enough jitter, 0 to 10% seems reasonable but it still a magic number.
