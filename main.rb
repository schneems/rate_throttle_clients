require_relative 'lib/rate_throttle_demo.rb'

require 'pathname'

client_dir = Pathname.new(__dir__).join('client')
client_dir.entries.each do |code|
  code = client_dir.join(code)
  load code.to_path if code.file?
end

begin
  HOUR = 3600
  MINUTE = 60
  duration = ENV.fetch("DURATION", 6*HOUR).to_i * MINUTE

  puts "=== Starting ==="
  client = ExponentialIncreaseSleepAndRemainingDecrease.new
  demo = RateThrottleDemo.new(client: client, stream_requests: true, duration: duration)
  demo.call

  puts "===== Done ====="
ensure
  puts demo.print_results
end
