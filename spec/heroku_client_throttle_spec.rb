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

  describe "decrement" do
    it "makes sleep_for go down faster when rate_limit_multiply_at is higher" do
      client = HerokuClientThrottle.new
      def client.sleep(val); end;

      @mock_time = Time.now

      client.stub(:rate_limit_multiply_at)
        .and_return(@mock_time)
      decrement_one = client.decrement_amount(FakeResponse.new, @mock_time)

      client.stub(:rate_limit_multiply_at)
        .and_return(@mock_time - 200)
      decrement_two = client.decrement_amount(FakeResponse.new, @mock_time)


      client.stub(:rate_limit_multiply_at)
        .and_return(@mock_time - 2000)
      decrement_three = client.decrement_amount(FakeResponse.new, @mock_time)

      expect(decrement_one < decrement_two).to be_truthy
      expect(decrement_two < decrement_three).to be_truthy

      # Test exponential decay behavior
      # client.stub(:rate_limit_multiply_at)
      #   .and_return(@mock_time - 200_000_000_000)
      # decrement_high = client.decrement_amount(FakeResponse.new, @mock_time)
    end

    it "makes sleep_for go down faster when remaining is higher" do
      client = HerokuClientThrottle.new
      @mock_time = Time.now

      remaining = 1
      decrement_one = client.decrement_amount(FakeResponse.new(200, remaining), @mock_time)

      remaining = 100
      decrement_two = client.decrement_amount(FakeResponse.new(200, remaining), @mock_time)

      remaining = 1000
      decrement_three = client.decrement_amount(FakeResponse.new(200, remaining), @mock_time)

      expect(decrement_one < decrement_two).to be_truthy
      expect(decrement_two < decrement_three).to be_truthy
    end

    it "sleep_for causes proportional rate reduction" do
      client = HerokuClientThrottle.new
      @mock_time = Time.now

      def client.sleep_for; 1; end
      decrement_one = client.decrement_amount(FakeResponse.new, @mock_time)

      def client.sleep_for; 10; end
      decrement_two = client.decrement_amount(FakeResponse.new, @mock_time)

      expect(decrement_one < decrement_two).to be_truthy

      expect(decrement_two).to be_between(decrement_one * 9.9, decrement_one * 10.1)
    end
  end
end