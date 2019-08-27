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
  @monitor = Monitor.new # Reentrant mutex
  @sleep_for = 2 * MIN_SLEEP
  @rate_limit_count = 0
  @times_retried = 0
  @retry_thread = nil

  def self.call(&block)
    jitter = @sleep_for * rand(0.0..0.1)
    sleep(@sleep_for + jitter)

    req = yield

    log(req)

    if retry_request?(req)
      req = retry_request_logic(&block)
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
      remaining = req.headers["RateLimit-Remaining"].to_i

      @sleep_for -= (remaining/(10*MAX_LIMIT/@sleep_for))
      @sleep_for = MIN_SLEEP if @sleep_for < 0
    end
  end

  def self.retry_request_logic(&block)
    i_am_retrying = false
    @monitor.synchronize do
      if @retry_thread_id.nil? || @retry_thread == Thread.current
        # First retry request, only increase sleep value if retry doesn't work.
        # Should guard against run-away high sleep values
        @sleep_for *= 2 if @times_retried != 0

        @times_retried += 1
        @retry_thread = Thread.current
        i_am_retrying = true
      end
    end

    # Retry the request with the new sleep value
    req = self.call(&block)
    if i_am_retrying
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

