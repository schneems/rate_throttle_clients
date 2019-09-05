# require 'pry'
RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.warnings = true
  if config.files_to_run.one?
    config.default_formatter = 'doc'
  end
  config.order = :random
  Kernel.srand config.seed
end

class FakeResponse
  attr_reader :status, :headers

  def initialize(status = 200, remaining = 10)
    @status = status

    @headers = {
      "RateLimit-Remaining" => remaining,
      "RateLimit-Multiplier" => 1,
      "Content-Type" => "text/plain".freeze
    }
  end
end