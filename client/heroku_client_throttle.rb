require 'thread'
require 'date'

class HerokuClientThrottle
  MAX_LIMIT = 4500.to_f
  MIN_SLEEP = 1/(MAX_LIMIT / 3600)
  MIN_SLEEP_OVERTIME_PERCENT = 1.0 - 0.9 # Allow min sleep to go lower than actually calculated value, must be less than 1

  attr_reader :rate_limit_multiply_at, :sleep_for

  def initialize
    @mutex = Mutex.new
    @sleep_for = 2 * MIN_SLEEP
    @rate_limit_count = 1
    @times_retried = 0
    @retry_thread = nil
    @min_sleep_bound = MIN_SLEEP * MIN_SLEEP_OVERTIME_PERCENT
    @rate_multiplier = 1
    @rate_limit_multiply_at = Time.now - 1800
  end

  def call(&block)
    jitter = @sleep_for * rand(0.0..0.1)
    sleep(@sleep_for + jitter)

    req = yield

    log(req)

    if retry_request?(req)
      req = retry_request_logic(req, &block)
      return req
    else
      decrement_logic(req)
      return req
    end
  end

  def decrement_logic(req)
    @mutex.synchronize do
      ratelimit_remaining = req.headers["RateLimit-Remaining"].to_i

      # The goal of this logic is to balance out rate limiting events,
      # to prevent one single "flappy" client.
      #
      # When a client was recently rate limitied the time factor will be high.
      # This is used to slow down the decrement logic so that other clients that
      # have not hit a rate limit in a long time can come down.
      # Equation is based on exponential decay
      seconds_since_last_multiply = Time.now - @rate_limit_multiply_at
      time_factor = 1.0/(1.0 - Math::E ** -(seconds_since_last_multiply/4500.0))

      @sleep_for -= (ratelimit_remaining*@sleep_for)/(time_factor*MAX_LIMIT)
      @sleep_for = @min_sleep_bound if @sleep_for < @min_sleep_bound
    end
  end

  def retry_request_logic(req, &block)
    @mutex.synchronize do
      if @retry_thread.nil? || @retry_thread == Thread.current
        @rate_multiplier = req.headers.fetch("RateLimit-Multiplier") { @rate_multiplier }.to_f
        @min_sleep_bound = (1/(@rate_multiplier * MAX_LIMIT / 4500))
        @min_sleep_bound *= MIN_SLEEP_OVERTIME_PERCENT

        # First retry request, only increase sleep value if retry doesn't work.
        # Should guard against run-away high sleep values
        if @times_retried != 0
          @sleep_for *= 2
          @rate_limit_count += 1
          @rate_limit_multiply_at = Time.now
        end

        @times_retried += 1
        @retry_thread = Thread.current
      end
    end

    # Retry the request with the new sleep value
    req = call(&block)
    if @retry_thread == Thread.current
      @mutex.synchronize do
        @times_retried = 0
        @retry_thread = nil
      end
    end
    return req
  end

  def retry_request?(req)
    req.status == 429
  end

  def log(req)
    @mutex.synchronize do
      File.open(LOG_FILE, 'a') { |f| f.puts("#{DateTime.now.iso8601},#{@sleep_for.to_s}") }
    end

    seconds_since_last_multiply = Time.now - @rate_limit_multiply_at
    remaining = req.headers["RateLimit-Remaining"].to_i
    status_string = String.new("")
    status_string << "#{Process.pid}##{Thread.current.object_id}: "
    status_string << "#status=#{req.status} "
    status_string << "#remaining=#{remaining} "
    status_string << "#rate_limit_count=#{@rate_limit_count} "
    status_string << "#seconds_since_last_multiply=#{seconds_since_last_multiply.ceil} "
    status_string << "#sleep_for=#{@sleep_for} "
    puts status_string
  end
end
