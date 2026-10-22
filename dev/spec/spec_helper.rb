# Plain RSpec, no Rails boot: the Builder DSL and registries are dependency-free,
# and the pry_ext pieces under test (ShortcutPlanner, ConsoleMethods memoization,
# Prompt rendering) need only ActiveRecord::Base for model discovery, never a
# database connection or a live Pry session.
require "active_record"
require "partitia/dev"
require "partitia/dev/pry_ext"

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

  # The registries are process-global module state with no public reset; clear
  # them before every example so registrations never leak between specs.
  config.before do
    %i[@namespaces @models @commands @prompt_segments @before_resets @reset_tasks].each do |ivar|
      Partitia::Dev.remove_instance_variable(ivar) if Partitia::Dev.instance_variable_defined?(ivar)
    end
    prompt = Partitia::Dev::PryExt::Prompt
    prompt.remove_instance_variable(:@segment_registry) if prompt.instance_variable_defined?(:@segment_registry)
  end
end
