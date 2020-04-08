require 'thread'

# Class used for reporting
class RateThrottleInfo
  attr_reader :sleep_for

  def initialize(sleep_for: )
    @sleep_for = sleep_for
  end
end

class ExponentialIncreaseGradualDecrease
  MAX_LIMIT = 4500.to_f
  MIN_SLEEP = 1/(MAX_LIMIT / 3600)
  SLEEP_KEY = :"_exponential_increase_gradual_decrease_throttle_rate_limit_count"

  attr_reader :log
  attr_accessor :minimum_sleep, :multiplier

  def initialize(log = ->(req, throttle) {})
    @minimum_sleep = MIN_SLEEP
    @multiplier = 1.2
    @log = log
    @sleep_for = 0
    @decrease = @minimum_sleep
  end

  def call(&block)
    sleep_for = @sleep_for
    sleep(sleep_for + jitter(sleep_for))

    while (req = yield) && req.status == 429
      sleep_for += @minimum_sleep

      log.call(req, RateThrottleInfo.new(sleep_for: sleep_for))

      sleep(sleep_for + jitter(sleep_for))
      sleep_for *= multiplier
    end

    if sleep_for >= @decrease
      sleep_for -= @decrease
    else
      sleep_for = 0
    end

    @sleep_for = sleep_for

    req
  end

  def jitter(sleep_for)
    sleep_for * rand(0.0..0.1)
  end
end

