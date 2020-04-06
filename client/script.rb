require_relative 'heroku_client_throttle.rb'
require_relative 'exponential_backoff_throttle.rb'
require_relative '../lib/rate_throttle_demo.rb'

puts "=== Starting ==="


client = ExponentialBackoffThrottle.new
demo = RateThrottleDemo.new(client, stream_requests: true)
demo.call

puts "===== Done ====="
puts demo.results
