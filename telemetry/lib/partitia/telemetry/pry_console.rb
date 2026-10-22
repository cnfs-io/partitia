module CnfsTelemetry
  # Console-facing tap on the notification bus, wholly independent of the
  # OpenTelemetry bridge. `notif!` toggles a subscriber that logs every cnfs
  # notification as it is published, so you can watch the emit side WITHOUT the
  # SDK, a collector, or the container stack running. It answers "are my events
  # firing, and with what payload?" directly.
  #
  # Contributed to cnfs_dev's console via `install!`, which the Railtie calls
  # from its `console` block (development/test console sessions only — the same
  # pattern chorus/okf use). At a Rails/Pry console:
  #
  #   notif!        # => telemetry notif ON  (now printing each cnfs.* event)
  #   notif!        # => telemetry notif OFF (toggles back off)
  #
  # The subscriber prints name, duration, and payload. It is attached to the same
  # prefixes the bridge uses, so what you see here is exactly what the bridge
  # would turn into spans.
  #
  # Only `notif!` is exposed as a console command. The helpers are deliberately
  # given obscure, prefixed names so they don't pollute the console's command
  # space, and the on/off state is a bare instance variable rather than a
  # queryable command.
  module PryConsole
    module_function

    # Register the `notif!` command with cnfs_dev's console. Guarded so
    # cnfs_telemetry never hard-depends on cnfs_dev; called from the Railtie's
    # `console` block, which only runs once a console session starts — by which
    # point cnfs_dev is loaded and its registries exist.
    def install!
      return unless defined?(CnfsDev)

      CnfsDev.console do |c|
        c.command(:notif!) { CnfsTelemetry::PryConsole.notif! }
      end
    end

    # THE toggle. Not subscribed -> subscribe; subscribed -> unsubscribe. Ends by
    # calling `notif`, so invoking it always echoes the resulting state.
    def notif!
      if @subscriber.nil?
        matcher = /\A(?:#{CnfsTelemetry.prefixes.map { |p| Regexp.escape(p) }.join("|")})/
        @subscriber = ActiveSupport::Notifications.subscribe(matcher) do |name, start, finish, _id, payload|
          ms = ((finish - start) * 1000).round(1)
          cnfs_telemetry_log("#{name} (#{ms}ms) #{cnfs_telemetry_format_payload(payload)}")
        end
      else
        ActiveSupport::Notifications.unsubscribe(@subscriber)
        @subscriber = nil
      end

      notif
    end

    # Current status string (no bang).
    def notif = "telemetry notif #{@subscriber.nil? ? "OFF" : "ON"}"

    # Drop the error keys the bridge treats specially; they are objects/arrays
    # that render as noise in a console line. Obscure name to stay out of the
    # console command space.
    def cnfs_telemetry_format_payload(payload)
      payload.reject { |k, _| %i[exception exception_object].include?(k) }.inspect
    end

    # Obscure name to stay out of the console command space.
    def cnfs_telemetry_log(message)
      line = "[telemetry] #{message}"
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger.debug(line)
      else
        puts line
      end
    end
  end
end
