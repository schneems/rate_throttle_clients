require_relative 'heroku_client_throttle.rb'
require_relative 'exponential_backoff_throttle.rb'

require 'excon'
require 'pathname'
require 'fileutils'
require 'date'
LOG_DIR = Pathname.new(__FILE__).join("../../logs/clients/#{Time.now.strftime('%Y-%m-%d-%H-%M-%s-%N')}")
FileUtils.mkdir_p(LOG_DIR)

THREAD_COUNT = ENV.fetch("THREAD_COUNT") { 5 }.to_i
PROCESS_COUNT = ENV.fetch("PROCESS_COUNT") { 2 }.to_i

logger = ->(req, throttle) do
  remaining = req.headers["RateLimit-Remaining"].to_i
  status_string = String.new("")
  status_string << "#{Process.pid}##{Thread.current.object_id}: "
  status_string << "#status=#{req.status} "
  status_string << "#remaining=#{remaining} "
  status_string << "#rate_limit_count=#{throttle.rate_limit_count} "


  if throttle.rate_limit_multiply_at
    seconds_since_last_multiply = Time.now - throttle.rate_limit_multiply_at
    status_string << "#seconds_since_last_multiply=#{seconds_since_last_multiply.ceil} "
  end

  status_string << "#sleep_for=#{throttle.sleep_for} "
  puts status_string
end
CLIENT_THROTTLE = ExponentialBackoffThrottle.new(logger)

if ENV["TIME_SCALE"]
  require 'timecop'
  Timecop.scale(ENV["TIME_SCALE"].to_f)
  TIME_SCALE = ENV["TIME_SCALE"].to_f
  def CLIENT_THROTTLE.sleep(val)
    super val/TIME_SCALE
  end
end

def run
  loop do
    CLIENT_THROTTLE.call do
      Excon.get("http://localhost:9292")
    end
  end
end

def spawn_threads
  threads = []
  THREAD_COUNT.times.each do
    threads << Thread.new do
      run
    end
  end
  threads.map(&:join)
end

PROCESS_COUNT.times.each do
  fork do
    LOG_FILE = LOG_DIR.join(Process.pid.to_s).to_s
    Thread.new do
      loop do
        CLIENT_THROTTLE.write_sleep_to_disk(LOG_FILE)
        sleep 1
      end
    end

    spawn_threads
  end
end

Process.waitall
