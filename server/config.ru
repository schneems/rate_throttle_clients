require_relative "../lib/rate_limit_fake_server.rb"

require 'timecop'

if ENV["TIME_SCALE"]
  require 'timecop'
  Timecop.scale(ENV["TIME_SCALE"].to_f)
end
starting_limit = ENV.fetch("STARTING_LIMIT", 0).to_i
run RateLimitFakeServer.new(starting_limit: starting_limit)
