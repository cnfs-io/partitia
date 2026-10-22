require "opentelemetry"

module Partitia
  module Telemetry
    # Translates one family of ActiveSupport::Notifications events into
    # OpenTelemetry spans. One Subscriber instance is registered per event-name
    # prefix (see Partitia::Telemetry.prefixes); ActiveSupport matches events whose name
    # starts with that prefix, so registering "okf" captures "okf.bundle.create",
    # "okf.button.render", and so on.
    #
    # Timing model: we register with the object-form subscribe API and open the
    # span in `start` / close it in `finish`. That makes the span cover the exact
    # wall-clock extent of the instrumented block, and \u2014 because OTel's Context is
    # a thread-local stack \u2014 any spans emitted *inside* the block (nested CNFS
    # events, or host Rails/Rack auto-instrumentation) nest correctly underneath.
    #
    # Span shape:
    # - name        = the event name verbatim ("okf.bundle.create")
    # - tracer      = the event's first dotted segment ("okf"), matching
    #                 Partitia::Support::Logging's component tag
    # - attributes  = each payload entry, flattened to "<prefix>.<key>" with a
    #                 primitive value; `:exception`/`:exception_object` are handled
    #                 specially (they mark the span errored, not as attributes)
    class Subscriber
      # Payload keys ActiveSupport (or the emitter) uses for error signalling;
      # never emitted as plain attributes.
      ERROR_KEYS = %i[exception exception_object].freeze

      class << self
        # Register a subscriber for `prefix` and return the subscription object so
        # the caller can later unsubscribe it. Uses a String (not Regexp) matcher
        # so ActiveSupport does prefix matching.
        def subscribe(prefix)
          ActiveSupport::Notifications.subscribe(prefix_matcher(prefix), new)
        end

        private

        # ActiveSupport treats a String subscriber name as an exact match and a
        # Regexp as a pattern. We want "first segment starts with prefix", so the
        # regexp allows more first-segment characters (the underscored module tail,
        # "partitia" -> "partitia_okf") before the segment boundary: a dot or the end.
        def prefix_matcher(prefix)
          /\A#{Regexp.escape(prefix)}[^.]*(\.|\z)/
        end
      end

      # --- ActiveSupport object-subscriber contract -------------------------
      # ActiveSupport calls #start when the instrumented block begins and #finish
      # when it ends, passing a shared `id` so we can pair them. We stash the live
      # span + its OTel context token on a per-(name,id) stack.

      def start(name, id, _payload)
        tracer = tracer_for(name)
        span = tracer.start_span(name)
        token = OpenTelemetry::Context.attach(
          OpenTelemetry::Trace.context_with_span(span)
        )
        stack_for(id).push([ span, token ])
      end

      def finish(name, id, payload)
        entry = stack_for(id).pop
        return unless entry

        span, token = entry
        apply_payload(span, name, payload)
        OpenTelemetry::Context.detach(token)
        span.finish
      ensure
        cleanup(id)
      end

      private

      # A tracer whose instrumentation-library name is the event's first dotted
      # segment, so "okf.bundle.create" traces under "okf" \u2014 same identifier the
      # logging mixin tags with.
      def tracer_for(name)
        component = name.to_s.split(".").first
        component = "partitia" if component.nil? || component.empty?
        OpenTelemetry.tracer_provider.tracer(component)
      end

      # Fold the notification payload onto the span: errors mark status, everything
      # else becomes a namespaced attribute when it is a value OTel accepts.
      def apply_payload(span, name, payload)
        prefix = name.to_s
        payload.each do |key, value|
          if ERROR_KEYS.include?(key)
            record_error(span, value)
            next
          end

          attr_value = coerce(value)
          next if attr_value.nil?

          span.set_attribute("#{prefix}.#{key}", attr_value)
        end
      end

      def record_error(span, value)
        case value
        when Exception
          span.record_exception(value)
          span.status = OpenTelemetry::Trace::Status.error(value.message)
        when Array # ActiveSupport's [class_name, message] form
          span.status = OpenTelemetry::Trace::Status.error(value.compact.join(": "))
        end
      end

      # OTel attribute values must be a String, Boolean, Integer, Float, or an
      # array of one of those. Coerce the common cases; drop anything else (return
      # nil) rather than raise inside instrumentation.
      def coerce(value)
        case value
        when String, Integer, Float, true, false then value
        when Symbol then value.to_s
        when Array
          mapped = value.map { |v| coerce(v) }
          mapped.all? { |v| !v.nil? } ? mapped : nil
        when nil then nil
        else value.to_s
        end
      end

      # Per-notification-id LIFO stacks. ActiveSupport can deliver overlapping
      # events with the same name on one thread (rare, but reentrant blocks do it),
      # so we key by id and keep a stack. Stored per-thread to stay isolated.
      def stacks
        Thread.current[:partitia_telemetry_spans] ||= Hash.new { |h, k| h[k] = [] }
      end

      def stack_for(id)
        stacks[id]
      end

      def cleanup(id)
        stacks.delete(id) if stacks[id].empty?
      end
    end
  end
end
