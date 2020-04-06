require_relative 'heroku_client_throttle.rb'
require_relative 'exponential_backoff_throttle.rb'
require_relative '../lib/rate_throttle_demo.rb'

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
demo = RateThrottleDemo.new(client, stream_requests: true)
demo.call

puts "===== Done ====="
puts demo.results
