require_relative '../client/heroku_client_throttle.rb'

describe 'Heroku client throttle' do
  it "Check when rate limit is triggered, the time since multiply changes" do
    client = HerokuClientThrottle.new
    def client.sleep(val); end;

    sleep_start = client.sleep_for
    multiply_at_start = client.rate_limit_multiply_at

    @times_called = 0
    client.call do
      @times_called += 1
      if client.rate_limit_count < 1
        FakeResponse.new(429)
      else
        FakeResponse.new
      end
    end

    sleep_end = client.sleep_for
    multiply_at_end = client.rate_limit_multiply_at

    expect(@times_called).to eq(3) # Once for initial 429, once for second 429, once for final 200
    expect(sleep_end).to be_between(sleep_start, sleep_start * 2.1)
    expect(multiply_at_end).to_not eq(multiply_at_start)
    expect(multiply_at_end).to be_between(multiply_at_start, Time.now)
  end
end