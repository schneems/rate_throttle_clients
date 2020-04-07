require_relative 'client/heroku_client_throttle.rb'
require_relative 'client/exponential_backoff_throttle.rb'
require_relative 'lib/rate_throttle_demo.rb'


begin
  HOUR = 3600

  puts "=== Starting ==="
  client = ExponentialBackoffThrottle.new
  demo = RateThrottleDemo.new(client: client, stream_requests: true, duration: 6 * HOUR)
  demo.call

  puts "===== Done ====="
ensure
  puts demo.results
end
