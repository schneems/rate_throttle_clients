require 'excon'
require 'pathname'
require 'fileutils'
require 'date'
require 'json'
require 'timecop'

class RateThrottleDemo
  THREAD_COUNT = ENV.fetch("THREAD_COUNT") { 5 }.to_i
  PROCESS_COUNT = ENV.fetch("PROCESS_COUNT") { 2 }.to_i
  RUN_TIME=ENV.fetch("RUN_TIME") { 10 }.to_i # Seconds
  LOG_DIR = Pathname.new(__FILE__).join("../../logs/clients/#{Time.now.strftime('%Y-%m-%d-%H-%M-%s-%N')}")
  TIME_SCALE = ENV.fetch("TIME_SCALE", 1).to_f

  def initialize(client, thread_count: THREAD_COUNT, process_count: PROCESS_COUNT, duration: RUN_TIME, log_dir: LOG_DIR, time_scale: TIME_SCALE)
    @client = client
    @thread_count = thread_count
    @process_count = process_count
    @duration = duration
    @log_dir = log_dir
    @time_scale = time_scale
    @threads = []
    @pids = []

    FileUtils.mkdir_p(@log_dir)
  end

  def results
    result_hash = {}

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

    unless @client.instance_variable_get(:"@time_scale")
      def @client.sleep(val)
        super val/@time_scale
      end
    end

    @client.instance_variable_set(:"@time_scale", @time_scale)

    Timecop.scale(@time_scale) do
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
        request_time += Time.now - begin_time
      end
    end

    retry_ratio = retry_count / request_count.to_f

    results = {
      request_time: request_time,
      retry_ratio: retry_ratio,
      request_count: request_count
    }

    File.open(@log_dir.join("#{Process.pid}:#{Thread.current.object_id}"), 'a') do |f|
      f.puts(results.to_json)
    end
  end
end

