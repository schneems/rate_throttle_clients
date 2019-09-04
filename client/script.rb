require_relative 'heroku_client_throttle.rb'

require 'excon'
require 'pathname'
require 'fileutils'
LOG_DIR = Pathname.new(__FILE__).join("../../logs/clients/#{Time.now.strftime('%Y-%m-%d-%H-%M-%s-%N')}")
FileUtils.mkdir_p(LOG_DIR)

CLIENT_COUNT = ENV.fetch("CLIENT_COUNT") { 5 }.to_i
PROCESS_COUNT = ENV.fetch("PROCESS_COUNT") { 2 }.to_i
CLIENT_THROTTLE = HerokuClientThrottle.new

def run
  loop do
    CLIENT_THROTTLE.call do
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

