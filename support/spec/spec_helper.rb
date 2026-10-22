require "cnfs_support"

Dir[File.join(__dir__, "support", "**", "*.rb")].sort.each { |file| require file }

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  # Logging keeps process-global state (backend, level registry). Reset before
  # every example so ordering never leaks configuration between specs.
  config.before do
    CnfsSupport::Logging.reset!
    CnfsSupport.reset_storage!
    OtelSpanCapture.reset!
  end
end
