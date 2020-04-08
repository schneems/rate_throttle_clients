# require 'bundler/gem_tasks'

begin
  require "rspec/core/rake_task"
  RSpec::Core::RakeTask.new(:spec)
  task default: [:spec]
rescue LoadError
end

require_relative 'lib/rate_throttle_demo.rb'
require 'pathname'

client_dir = Pathname.new(__dir__).join('client')
client_dir.entries.each do |code|
  code = client_dir.join(code)
  load code.to_path if code.file?
end


minute = 60
task "bench:workload" do
  sleep_for = 10
  clients = [
    # ExponentialBackoffThrottle.new(),
    ExponentialIncreaseSleepAndRemainingDecrease.new(sleep_for: sleep_for),
    HerokuClientThrottle.new(sleep_for: sleep_for),
  ]
  clients.each do |client|
    before_time = Time.now
    demo = RateThrottleDemo.new(client: client, time_scale: 8, starting_limit: 4500, duration: 60 * minute, remaining_stop_under: 10)
    demo.call
    diff = Time.now - before_time

    puts
    puts "## #{client.class}"
    puts
    puts "Time to clear workload: #{diff} seconds"
  end
end

task "bench" do
  duration = ENV.fetch("DURATION", 30).to_i * minute
  puts "Simulation duration: #{duration / 60.0} minutes"

  clients = [ExponentialIncreaseGradualDecrease.new, HerokuClientThrottle.new]
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
