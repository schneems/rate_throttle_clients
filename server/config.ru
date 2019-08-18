require 'thread'

MAX_REQUESTS = 4500
limit_left = MAX_REQUESTS.to_f
last_request = Time.now
rate_of_limit_gain = limit_left / 3600
mutex = Mutex.new

app = -> (env) do
  mutex.synchronize do
    limit_left -= 1 if limit_left > 0

    if limit_left < MAX_REQUESTS
      current_request = Time.now
      time_diff = current_request - last_request
      last_request = current_request
      puts "current: #{current_request}, last: #{last_request} Time Left: #{limit_left} diff between requests: #{time_diff} addition: #{limit_left + time_diff * rate_of_limit_gain}"
      limit_left = [limit_left + time_diff * rate_of_limit_gain, MAX_REQUESTS].min
    end
  end

  remaining = [limit_left.floor, 0].max
  headers = { "RateLimit-Remaining" => remaining, "Content-Type" => "text/plain" }
  if remaining <= 0
    status = 429
    body = "!!!!! Nope !!!!!"
  else
    status = 200
    body = "<3<3<3 Hello world <3<3<3"
  end

  puts headers.inspect
  return [status, headers, [body]]
end

run app
