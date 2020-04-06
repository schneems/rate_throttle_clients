require 'excon'
require 'pathname'
require 'fileutils'
require 'date'
require 'json'
require 'timecop'

Thread.abort_on_exception = true

class RateThrottleDemo
  THREAD_COUNT = ENV.fetch("THREAD_COUNT") { 5 }.to_i
  PROCESS_COUNT = ENV.fetch("PROCESS_COUNT") { 2 }.to_i
  RUN_TIME=ENV.fetch("RUN_TIME") { 10 }.to_i # Seconds
  LOG_DIR = Pathname.new(__dir__).join("../logs/clients/#{Time.now.strftime('%Y-%m-%d-%H-%M-%s-%N')}")
  TIME_SCALE = ENV.fetch("TIME_SCALE", 1).to_f
  RACKUP_FILE = Pathname.new(__dir__).join("../server/config.ru")

  def initialize(client:,thread_count: THREAD_COUNT, process_count: PROCESS_COUNT, duration: RUN_TIME, log_dir: LOG_DIR, time_scale: TIME_SCALE, stream_requests: false, json_duration: 30, rackup_file: RACKUP_FILE)
    @client = client
    @thread_count = thread_count
    @process_count = process_count
    @duration = duration
    @log_dir = log_dir
    @time_scale = time_scale
    @stream_requests = stream_requests
    @json_duration = json_duration
    @rackup_file = rackup_file
    @threads = []
    @pids = []

    FileUtils.mkdir_p(@log_dir)
  end

  def results
    result_hash = {}

    @log_dir.entries.map do |entry|
      @log_dir.join(entry)
    end.select do |file|
      file.file? && file.extname == ".json"
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
    WaitForIt.new("bundle exec puma #{@rackup_file.to_s}", env: {"TIME_SCALE" => @time_scale.to_i.to_s}, wait_for: "Use Ctrl-C to stop") do |spawn|
      @process_count.times.each do
        @pids << fork do
          run_threads
        end
      end

      @pids.map { |pid| Process.wait(pid) }
    end
  end

  private def run_threads
    @thread_count.times.each do
      @threads << Thread.new do
        run_client_single
      end
    end

    # Chart support, print out the sleep value in 1 second increments
    Thread.new do
      loop do
        @threads.each do |thread|
          sleep_for = thread.thread_variable_get("last_sleep_value") || 0

          File.open(@log_dir.join("#{Process.pid}:#{thread.object_id}-chart-data.txt"), 'a') do |f|
            f.puts(sleep_for)
          end
        end
        sleep 1 # time gets adjusted via TIME_SCALE later in time.rb
      end
    end

    @threads.map(&:join)
  end

  private def run_client_single
    end_at_time = Time.now + @duration
    next_json_time = Time.now + @json_duration
    request_count = 0
    retry_count = 0

    if !@client.instance_variable_get(:"@time_scale")
      def @client.sleep(val)
        @max_sleep_val = val if val > @max_sleep_val
        Thread.current.thread_variable_set("last_sleep_value", val)

        super val/@time_scale
      end

      def @client.max_sleep_val
        @max_sleep_val
      end

      def @client.last_sleep
        @last_sleep || 0
      end
    end

    @client.instance_variable_set(:"@time_scale", @time_scale)
    @client.instance_variable_set(:"@max_sleep_val", 0)

    Timecop.scale(@time_scale) do
      loop do
        begin_time = Time.now
        break if begin_time > end_at_time
        if begin_time > next_json_time
          write_json_value(retry_count: retry_count, request_count: request_count, max_sleep_val: @client.max_sleep_val)
          next_json_time = begin_time + @json_duration
        end

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

          if @stream_requests
            status_string = String.new
            status_string << "#{Process.pid}##{Thread.current.object_id}: "
            status_string << "status=#{request.status} "
            status_string << "remaining=#{request.headers["RateLimit-Remaining"]} "
            status_string << "retry_count=#{retry_count} "
            status_string << "request_count=#{request_count} "
            status_string << "max_sleep_val=#{ sprintf("%.2f", @client.max_sleep_val) } "

            puts status_string
          end

          request
        end
      end
    end

    write_json_value(retry_count: retry_count, request_count: request_count, max_sleep_val: @client.max_sleep_val)
  end

  private def write_json_value(retry_count:, request_count:, max_sleep_val:)
    results = {
      max_sleep_val: max_sleep_val,
      retry_ratio: retry_count / request_count.to_f,
      request_count: request_count
    }

    File.open(@log_dir.join("#{Process.pid}:#{Thread.current.object_id}.json"), 'w+') do |f|
      f.puts(results.to_json)
    end
  end
end

