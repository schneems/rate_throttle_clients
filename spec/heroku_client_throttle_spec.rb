require_relative '../client/heroku_client_throttle.rb'

describe 'Heroku client throttle' do
  it "Check when rate limit is triggered, the time since multiply changes" do
    client = HerokuClientThrottle.new
    def client.sleep(val); end;

    sleep_start = client.sleep_for
    client.call do
      if client.rate_limit_count < 1
        FakeResponse.new(429)
      else
        FakeResponse.new
      end
    end

    sleep_end = client.sleep_for
    expect(sleep_end).to be_between(sleep_start, sleep_start * 2.1)
  end
end