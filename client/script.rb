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
  @monitor = Monitor.new # Reentrant mutex
  @arrival_rate = MAX_LIMIT
  @client_guess = nil
  @rate_limit_count = 0
  @multiplier = 1

  def self.sleep_for_client_count
    return 0 if @client_guess.nil?
    return 0 if @client_guess < 0

    sleep_for = @client_guess * 1/(@arrival_rate / 3600)
    jitter = sleep_for * rand(0.0..0.1)
    return sleep_for + jitter
  end

  def self.log(req, sleep_for)
    @monitor.synchronize do
      File.open(LOG_FILE, 'a') { |f| f.puts("#{DateTime.now.iso8601},#{sleep_for.to_s}") }
    end
  end

  def self.call(times_retried = 0, &block)
    rate_limit_count = @rate_limit_count

    sleep_for = sleep_for_client_count
    sleep(sleep_for)

    req = yield

    remaining = req.headers["RateLimit-Remaining"].to_i

    status_string = String.new("")
    status_string << "#{Process.pid}##{Thread.current.object_id}: "
    status_string << "#status=#{req.status} "
    status_string << "#client_guess=#{@client_guess || 0} "
    status_string << "#remaining=#{remaining} "
    status_string << "#sleep_for=#{sleep_for} "
    puts status_string
    log(req, sleep_for)

    @monitor.synchronize do
      if req.status == 429
        # This was tough to figure out
        #
        # Basically when we hit a rate limiting event, we don't want all
        # threads to be increasing the guess size, really just the first client
        # to do the job of figuring how much it should slow down. The other jobs
        # should sit and wait for a number they can try.
        #
        # If this value is different than the value recorded at the beginning of the
        # request then it means another thread has already increased the client guess
        # and we should try using that value first before we try bumping it.
        if rate_limit_count == @rate_limit_count
          @client_guess ||= 0
          @client_guess += 1
          @rate_limit_count += 1

          # First retry with current sleep value, only when it's not enough increase
          @client_guess *= 2 if times_retried != 0

          @multiplier = req.headers.fetch("RateLimit-Multiplier") { @multiplier }.to_f

          @arrival_rate = @multiplier * MAX_LIMIT
        end

        # Retry the request with the new sleep value
        req = self.call(times_retried + 1, &block)
      else
        # The fewer available requests, the slower we should reduce our client guess.
        # We want this to converge and linger around a correct value rather than
        # being a true sawtooth pattern.
        if @client_guess
          @client_guess -= remaining / MAX_LIMIT
          @client_guess = 0 if @client_guess < 0
        end
      end
    end

    return req
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

