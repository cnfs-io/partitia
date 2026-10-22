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

      # Opt-in log↔trace bridge. When true AND OpenTelemetry is loaded in the
      # host (only the case when cnfs_telemetry + its SDK are wired) AND a
      # recording span is on the context, each emitted line is mirrored as a
      # span event on that span. Default OFF: correlation is deliberately opt-in.
      # `cnfs_support` never hard-references OpenTelemetry — the emit path reaches
      # it only through a runtime `defined?` probe (see TaggedLogger#bridge_span).
      def bridge_to_spans
        @bridge_to_spans || false
      end

      attr_writer :bridge_to_spans

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
        @bridge_to_spans = nil
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

          # Evaluate the block exactly once; the value feeds both the backend
          # line and (when bridging) the span event.
          message = block.call if block
          result = CnfsSupport::Logging.backend.public_send(level, "[#{@tag}] #{message}")
          bridge_span(message, level) if CnfsSupport::Logging.bridge_to_spans
          result
        end

        # Level predicate (`info?`, `debug?`, …). Rails and other Logger-aware
        # callers probe these before building an expensive message, and because
        # this logger is now mixed onto every ApplicationController, the render
        # path calls them every request. Answer from the per-tag level so the
        # predicate matches what an actual emit at that level would do.
        define_method("#{level}?") { enabled?(level) }
      end

      # True when a call at `level` clears the tag's configured floor.
      def enabled?(level)
        LEVELS.index(level) >= LEVELS.index(CnfsSupport::Logging.level_for(@tag))
      end

      private

      # Attach this line to the currently-active span as a span event, if any.
      # Reaches OpenTelemetry ONLY through a runtime `defined?` probe so
      # `cnfs_support` keeps zero OTel dependency at load time — the constant is
      # present only when the host runs cnfs_telemetry + an OTel SDK. Silent when
      # no span is on the context (the common case) or the span is non-recording.
      # `log.tag` preserves the line's own component identity even when it rides a
      # span opened by a different component's instrument(...) block.
      def bridge_span(message, level)
        return unless defined?(OpenTelemetry)

        span = OpenTelemetry::Trace.current_span
        return unless span.recording?

        span.add_event(
          message.to_s,
          attributes: { "log.severity" => level.to_s, "log.tag" => @tag }
        )
      end
    end
  end
end
