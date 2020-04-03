require 'thread'

class RateThrottleInfo
  attr_reader :rate_limit_multiply_at, :rate_limit_count, :sleep_for

  def initialize(rate_limit_multiply_at: , rate_limit_count: , sleep_for: )
    @rate_limit_multiply_at = rate_limit_multiply_at
    @rate_limit_count = rate_limit_count
    @sleep_for = sleep_for
  end
end

class ExponentialBackoffThrottle
  MAX_LIMIT = 4500.to_f
  MIN_SLEEP = 1/(MAX_LIMIT / 3600)

  attr_reader :rate_limitultiply_at, :sleep_for, :rate_limit_count, :log
  attr_accessor :minimum_sleep, :multiplier

  def initialize(log = ->(req, throttle) {})
    @minimum_sleep = MIN_SLEEP
    @multiplier = 2
    @log = log
  end


  def call(&block)
    sleep_for = nil
    rate_limit_multiply_at = nil

    Thread.current[:"_exponential_backoff_throttle_rate_limit_count"] ||= 0

    while ((req = yield) && req.status == 429)
      rate_limit_multiply_at ||= Time.now
      Thread.current[:"_exponential_backoff_throttle_rate_limit_count"] += 1

      sleep_for ||= @minimum_sleep

      info = RateThrottleInfo.new(
        sleep_for: sleep_for,
        rate_limit_count: Thread.current[:"_exponential_backoff_throttle_rate_limit_count"],
        rate_limit_multiply_at: rate_limit_multiply_at
      )
      log.call(req, info)
      jitter = sleep_for * rand(0.0..0.1)

      sleep(sleep_for + jitter)

      sleep_for *= multiplier
    end

    req
  end
end

