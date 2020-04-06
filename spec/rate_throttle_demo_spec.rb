require_relative 'spec_helper.rb'
require_relative '../lib/rate_throttle_demo.rb'

describe 'Rate throttle demo' do
  it "aggregates a bunch of json files into one hash" do
    dir = fixture_path("rtd_logs/90_sec_json_logs")
    demo = RateThrottleDemo.new(Object.new, log_dir: dir)

    expected = {"max_sleep_val"=>[53.88212537937639, 56.069378305278775, 53.88212537937639, 56.069378305278775, 56.069378305278775, 53.88212537937639, 56.069378305278775, 53.88212537937639, 56.069378305278775, 53.88212537937639], "retry_ratio"=>[0.35036496350364965, 0.10606060606060606, 0.10294117647058823, 0.29464285714285715, 0.125, 0.21686746987951808, 0.1111111111111111, 0.36627906976744184, 0.10606060606060606, 0.10144927536231885], "request_count"=>[137, 66, 68, 112, 72, 83, 63, 172, 66, 69]}

    expect(demo.results).to eq(expected)
  end
end
