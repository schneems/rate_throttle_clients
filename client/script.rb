require 'thread'
require 'excon'

CLIENT_COUNT = ENV.fetch("CLIENT_COUNT") { 5 }.to_i
PROCESS_COUNT = ENV.fetch("PROCESS_COUNT") { 2 }.to_i

module RateLimit
  @mutex = Mutex.new
  @sleep_for = 0.5
  @max_remaining = 4500.to_f

  def self.call(&block)
    jitter = @sleep_for * rand(0.0..0.1)
    sleep(@sleep_for + jitter)

    req = yield

    remaining = req.headers["RateLimit-Remaining"].to_i

    status_string = String.new("")
    status_string << "#{Process.pid}##{Thread.current.object_id}: "
    status_string << "#status=#{req.status} "
    status_string << "#remaining=#{remaining} "
    status_string << "#sleep_for=#{@sleep_for} "
    puts status_string

    if req.status == 429
      @sleep_for *= 1.2

      req = self.call(&block)
    else
      if @sleep_for > (remaining / @max_remaining )
        @sleep_for -= remaining / @max_remaining
      else
        @sleep_for = 0.001
      end
    end

    return req
  end

end


def run
  loop do
    RateLimit.call do
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

def spawn_processes
  PROCESS_COUNT.times.each do
    fork do
      spawn_threads
    end
  end

  Process.waitall
end

spawn_processes

