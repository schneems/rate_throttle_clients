require 'thread'

RATE_LIMIT_COUNT_KEY = :"_exponential_backoff_throttle_rate_limit_count"

# Class used for reporting
class RateThrottleInfo
  attr_reader :sleep_for

  def initialize(sleep_for: )
    @sleep_for = sleep_for
  end
end


# Actual exponential backoff class with some extra jazz so it reports
# kinda like the HerokuRateThrottle class
#
# Essentially it doesn't throttle at all until it hits a 429 then it exponentially
# throttles every repeatedly limited request. When it hits a successful request it stops
# rate throttling again.
#
class ExponentialBackoffThrottle
  MAX_LIMIT = 4500.to_f
  MIN_SLEEP = 1/(MAX_LIMIT / 3600)

  attr_reader :log
  attr_accessor :minimum_sleep, :multiplier

  def initialize(log = ->(req, throttle) {})
    @minimum_sleep = MIN_SLEEP
    @multiplier = 2
    @log = log
  end

  def call(&block)
    sleep_for = @minimum_sleep

    while (req = yield) && req.status == 429
      log.call(req, RateThrottleInfo.new(sleep_for: sleep_for))

      sleep(sleep_for + jitter(sleep_for))
      sleep_for *= multiplier
    end

    sleep(0) # reset value for chart

    req
  end

  def jitter(sleep_for)
    sleep_for * rand(0.0..0.1)
  end
end

