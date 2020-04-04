require 'thread'

RATE_LIMIT_COUNT_KEY = :"_exponential_backoff_throttle_rate_limit_count"

# Class used for reporting
class RateThrottleInfo
  attr_reader :rate_limit_multiply_at, :rate_limit_count, :sleep_for

  def initialize(rate_limit_count: Thread.current[RATE_LIMIT_COUNT_KEY], sleep_for: )
    @rate_limit_count = rate_limit_count
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
    @thread_sleeps_hash = {}
  end

  def call(&block)
    # Needed to log out to build consistent chart
    @thread_sleeps_hash[Thread.current] = 0

    sleep_for = @minimum_sleep

    while (req = yield) && req.status == 429
      Thread.current[RATE_LIMIT_COUNT_KEY] ||= 0
      Thread.current[RATE_LIMIT_COUNT_KEY] += 1

      @thread_sleeps_hash[Thread.current] = sleep_for

      # Log failed requests
      log.call(req, RateThrottleInfo.new(sleep_for: sleep_for))

      sleep(sleep_for + jitter(sleep_for))
      sleep_for *= multiplier
    end

    # Log success requests
    log.call(req, RateThrottleInfo.new(sleep_for: 0))

    req
  end

  def jitter(sleep_for)
    sleep_for * rand(0.0..0.1)
  end

  # Used to generate charts
  def write_sleep_to_disk(log_dir)
    @thread_sleeps_hash.each do |thread, sleep_for|
      File.open("#{LOG_FILE}##{thread.object_id}", 'a') do |f|
        f.puts("#{sleep_for}")
      end
    end
  end
end

