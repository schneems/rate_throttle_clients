require_relative 'heroku_client_throttle.rb'
require_relative 'exponential_backoff_throttle.rb'

require 'excon'
require 'pathname'
require 'fileutils'
require 'date'
require 'json'

if ENV["TIME_SCALE"]
  require 'timecop'
  Timecop.scale(ENV["TIME_SCALE"].to_f)
  TIME_SCALE = ENV["TIME_SCALE"].to_f
  def CLIENT_THROTTLE.sleep(val)
    super val/TIME_SCALE
  end
end

LOG_DIR = Pathname.new(__FILE__).join("../../logs/clients/#{Time.now.strftime('%Y-%m-%d-%H-%M-%s-%N')}")

class RateThrottleDemo
  THREAD_COUNT = ENV.fetch("THREAD_COUNT") { 5 }.to_i
  PROCESS_COUNT = ENV.fetch("PROCESS_COUNT") { 2 }.to_i
  RUN_TIME=ENV.fetch("RUN_TIME") { 10 }.to_i # Seconds

  def initialize(client, thread_count: THREAD_COUNT, process_count: PROCESS_COUNT, duration: RUN_TIME, log_dir: LOG_DIR)
    @client = client
    @thread_count = thread_count
    @process_count = process_count
    @duration = duration
    @log_dir = log_dir
    @threads = []
    @pids = []

    FileUtils.mkdir_p(@log_dir)
  end

  def results
    result_hash = {}
    puts @log_dir

    @log_dir.entries.map do |entry|
      @log_dir.join(entry)
    end.select do |file|
      file.file?
    end.map do |file|
      JSON.parse(file.read)
    end.each do |json|
      json.each_key do |key|
        result_hash[key] ||= []
        result_hash[key] << json[key]
      end
    end

    result_hash
  end

  def call
    @process_count.times.each do
      @pids << fork do
        run_threads
      end
    end

    @pids.map { |pid| Process.wait(pid) }
  end

  private def run_threads
    @thread_count.times.each do
      @threads << Thread.new do
        run_client_single
      end
    end
    @threads.map(&:join)
  end

  private def run_client_single
    start_time = Time.now
    end_time = start_time + @duration
    request_count = 0
    retry_count = 0
    request_time = 0

    loop do
      begin_time = Time.now
      break if begin_time > end_time

      @client.call do
        request_count += 1

        request = Excon.get("http://localhost:9292")

        case request.status
        when 200
        when 429
          retry_count += 1
        else
          raise "Got unexpected reponse #{request.status}. #{request.inspect}"
        end

        request
      end
      elapsed = Time.now - begin_time
      request_time += elapsed
    end

    retry_ratio = retry_count / request_count.to_f

    results = {
      request_time: request_time,
      retry_ratio: retry_ratio,
      request_count: request_count
    }

    puts results.inspect

    File.open(@log_dir.join("#{Process.pid}:#{Thread.current.object_id}"), 'a') do |f|
      f.puts(results.to_json)
    end
  end
end

# throttle.distribution (needs request)
# throttle.retry_ratios (needs success count, retry count)
# throttle.sleep_times (needs time to make a success request)

# logger = ->(req, throttle) do
#   remaining = req.headers["RateLimit-Remaining"].to_i
#   status_string = String.new("")
#   status_string << "#{Process.pid}##{Thread.current.object_id}: "
#   status_string << "#status=#{req.status} "
#   status_string << "#remaining=#{remaining} "
#   status_string << "#rate_limit_count=#{throttle.rate_limit_count} "
#
#   if throttle.rate_limit_multiply_at
#     seconds_since_last_multiply = Time.now - throttle.rate_limit_multiply_at
#     status_string << "#seconds_since_last_multiply=#{seconds_since_last_multiply.ceil} "
#   end

#   status_string << "#sleep_for=#{throttle.sleep_for} "
#   puts status_string
# end

puts "=== Starting ==="
client = ExponentialBackoffThrottle.new
throttle = RateThrottleDemo.new(client)
throttle.call

puts "=== done ==="
puts throttle.results
