require 'monitor'
require 'excon'

require 'date'
require 'pathname'
require 'fileutils'
LOG_DIR = Pathname.new(__FILE__).join("../logs/clients/#{Time.now.strftime('%Y-%m-%d-%H-%M-%s-%N')}")
FileUtils.mkdir_p(LOG_DIR)

CLIENT_COUNT = ENV.fetch("CLIENT_COUNT") { 5 }.to_i
PROCESS_COUNT = ENV.fetch("PROCESS_COUNT") { 2 }.to_i
module RateLimit
  MAX_LIMIT = 4500.to_f
  MIN_SLEEP = 1/(MAX_LIMIT / 3600)
  MIN_SLEEP_OVERTIME_PERCENT = 1.0 - 0.45 # Allow min sleep to go lower than actually calculated value, must be less than 1
  @monitor = Monitor.new # Reentrant mutex
  @sleep_for = 2 * MIN_SLEEP
  @rate_limit_count = 1
  @times_retried = 0
  @retry_thread = nil
  @min_sleep_bound = MIN_SLEEP
  @rate_multiplier = 1

  def self.call(&block)
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

  # The fewer available requests, the slower we should reduce our client guess.
  # We want this to converge and linger around a correct value rather than
  # being a true sawtooth pattern.
  def self.decrement_logic(req)
    @monitor.synchronize do
      ratelimit_remaining = req.headers["RateLimit-Remaining"].to_i

      @sleep_for -= (ratelimit_remaining*@sleep_for)/(@rate_limit_count*MAX_LIMIT)
      @sleep_for = @min_sleep_bound if @sleep_for < @min_sleep_bound
    end
  end

  def self.retry_request_logic(req, &block)
    @monitor.synchronize do
      if @retry_thread.nil? || @retry_thread == Thread.current
        @rate_multiplier = req.headers.fetch("RateLimit-Multiplier") { @rate_multiplier }.to_f
        @min_sleep_bound = (1/(@rate_multiplier * MAX_LIMIT / 3600))
        @min_sleep_bound *= MIN_SLEEP_OVERTIME_PERCENT

        # First retry request, only increase sleep value if retry doesn't work.
        # Should guard against run-away high sleep values
        if @times_retried != 0
          @sleep_for *= 2
          @rate_limit_count += 1
        end

        @times_retried += 1
        @retry_thread = Thread.current
      end
    end

    # Retry the request with the new sleep value
    req = self.call(&block)
    if @retry_thread == Thread.current
      @monitor.synchronize do
        @times_retried = 0
        @retry_thread = nil
      end
    end
    return req
  end

  def self.retry_request?(req)
    req.status == 429
  end

  def self.log(req)
    @monitor.synchronize do
      File.open(LOG_FILE, 'a') { |f| f.puts("#{DateTime.now.iso8601},#{@sleep_for.to_s}") }
    end

    remaining = req.headers["RateLimit-Remaining"].to_i
    status_string = String.new("")
    status_string << "#{Process.pid}##{Thread.current.object_id}: "
    status_string << "#status=#{req.status} "
    status_string << "#remaining=#{remaining} "
    status_string << "#rate_limit_count=#{@rate_limit_count} "
    status_string << "#sleep_for=#{@sleep_for} "
    puts status_string
  end
end


def run
  loop do
    RateLimit.call do
      Excon.get("http://localhost:9292")
    end
  end
end

def spawn_threads
  threads = []
  CLIENT_COUNT.times.each do
    threads << Thread.new do
      run
    end
  end
  threads.map(&:join)
end

PROCESS_COUNT.times.each do
  fork do
    LOG_FILE = LOG_DIR.join(Process.pid.to_s).to_s
    spawn_threads
  end
end

Process.waitall

