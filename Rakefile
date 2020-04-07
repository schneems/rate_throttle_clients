# require 'bundler/gem_tasks'

begin
  require "rspec/core/rake_task"
  RSpec::Core::RakeTask.new(:spec)
  task default: [:spec]
rescue LoadError
end

require_relative 'client/heroku_client_throttle.rb'
require_relative 'client/exponential_backoff_throttle.rb'
require_relative 'lib/rate_throttle_demo.rb'

task "bench" do
  minute = 60
  duration = ENV.fetch("DURATION", 30).to_i * minute
  puts "Simulation duration: #{duration / 60.0} minutes"

  clients = [ExponentialBackoffThrottle.new, HerokuClientThrottle.new]
  clients.each do |client|
    demo = RateThrottleDemo.new(client: client, duration: duration, time_scale: 8)
    demo.call

    puts
    puts "## Raw #{client.class} results"
    puts
    results = demo.results

    results["max_sleep_val"]
    results["retry_ratio"]
    results["max_sleep_val"]

    demo.results.each do |key, value|
      puts "#{key}: [#{ value.map {|x| "%.2f" % x}.join(", ")}]"
    end
  end
end
