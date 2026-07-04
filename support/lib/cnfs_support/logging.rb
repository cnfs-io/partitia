require "active_support/concern"
require "logger"

module CnfsSupport
  # Tagged, per-component logging with independent per-tag verbosity and a
  # host-swappable backend.
  #
  #   module Okf
  #     class Button
  #       include CnfsSupport::Logging
  #
  #       def render
  #         logger.debug { "rendering #{self.class}" }
  #       end
  #     end
  #   end
  #
  # `Okf::Button` gets a logger tagged `okf` (the first namespace segment; see
  # CnfsSupport.component_tag). The host controls verbosity independently per
  # tag and can swap the underlying backend.
  #
  # This is a deliberately thin, independent layer — NOT a wrapper over
  # ActiveSupport::TaggedLogging/BroadcastLogger. Rails' single global level
  # can't give per-gem verticality, and wrapping TaggedLogging would reintroduce
  # the Rails coupling this gem exists to avoid. The backend defaults to
  # Rails.logger only when Rails is already present, else a plain stdlib Logger,
  # so the mixin is fully usable pre-boot in a non-Rails context.
  module Logging
    extend ActiveSupport::Concern

    LEVELS = %i[debug info warn error fatal].freeze

    # Instances delegate to their class-level logger so every instance of a
    # class shares one tagged logger.
    def logger
      self.class.logger
    end

    class_methods do
      def logger
        @logger ||= CnfsSupport::Logging.build_for(name)
      end
    end

    class << self
      # Explicit host override wins; otherwise resolve a sensible default each
      # call so the degrade path (Rails absent) and host swaps both take effect
      # even for already-built TaggedLoggers.
      def backend
        @backend || default_backend
      end

      attr_writer :backend

      # Per-tag verbosity registry. `levels[:default]` is the floor; a string
      # key overrides one tag, e.g. `levels["okf"] = :debug`.
      def levels
        @levels ||= { default: :info }
      end

      # The effective level for a tag: its own override, else the floor, else :info.
      def level_for(tag)
        levels[tag] || levels[:default] || :info
      end

      def build_for(name)
        TaggedLogger.new(CnfsSupport.component_tag(name))
      end

      # Reset memoized state — used by specs to isolate examples.
      def reset!
        @backend = nil
        @levels = nil
      end

      private

      def default_backend
        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger
        else
          ::Logger.new($stdout)
        end
      end
    end

    # Wraps the shared backend: prefixes each line with `[tag]` and filters by
    # the per-tag level. Supports the block form and never evaluates the block
    # when the level is disabled.
    class TaggedLogger
      attr_reader :tag

      def initialize(tag)
        @tag = tag
      end

      LEVELS.each do |level|
        define_method(level) do |message = nil, &block|
          return false unless enabled?(level)

          message = block.call if block
          CnfsSupport::Logging.backend.public_send(level, "[#{@tag}] #{message}")
        end
      end

      # True when a call at `level` clears the tag's configured floor.
      def enabled?(level)
        LEVELS.index(level) >= LEVELS.index(CnfsSupport::Logging.level_for(@tag))
      end
    end
  end
end
