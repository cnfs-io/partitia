# Capturing backend for Partitia::Support::Logging. The TaggedLogger emits each line
# to Partitia::Support::Logging.backend as a single "[tag] message" string; this fake
# records (level, message) so examples can assert level routing, tag
# correctness, and — the point of it — that no sensitive material ever appears.
#
# Opt in per example with the `:logs` metadata tag. The hooks swap the backend,
# drop the floor to :debug so debug lines are assertable, and restore defaults
# via Partitia::Support::Logging.reset! afterward so examples stay isolated.
module LogCapture
  Line = Struct.new(:level, :message)

  class Backend
    attr_reader :lines

    def initialize
      @lines = []
    end

    Partitia::Support::Logging::LEVELS.each do |level|
      define_method(level) do |message = nil, &block|
        message = block.call if block
        @lines << Line.new(level, message.to_s)
        true
      end
    end

    # Every captured message string (each already carries its "[tag]" prefix).
    def messages
      lines.map(&:message)
    end

    def joined
      messages.join("\n")
    end

    # Messages captured at a single level.
    def at(level)
      lines.select { |line| line.level == level }.map(&:message)
    end

    # Messages carrying the given "[tag]" prefix.
    def tagged(tag)
      messages.select { |message| message.start_with?("[#{tag}]") }
    end
  end

  module Helpers
    def captured_log
      @captured_log
    end
  end
end

RSpec.configure do |config|
  config.include LogCapture::Helpers, :logs

  config.before(:each, :logs) do
    @captured_log = LogCapture::Backend.new
    Partitia::Support::Logging.backend = @captured_log
    Partitia::Support::Logging.levels[:default] = :debug
  end

  config.after(:each, :logs) do
    Partitia::Support::Logging.reset!
  end
end
