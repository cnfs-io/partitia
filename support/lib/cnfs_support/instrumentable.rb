require "active_support/concern"
require "active_support/isolated_execution_state"
require "active_support/notifications"
require "active_support/core_ext/string/inflections"

module CnfsSupport
  # Emit standardized ActiveSupport::Notifications events from a model (or any
  # class) with zero telemetry coupling. Owns the notification *ceremony* so
  # callers never hand-type an event name: the name is composed from the class
  # itself, so it is always correct and always consistent.
  #
  #   module CnfsOkf
  #     class Bundle
  #       include CnfsSupport::Instrumentable
  #
  #       def create_concepts
  #         instrument(:create, bundle_id: id, path: path) do |payload|
  #           created = concept_paths.map { |p| concepts.find_or_create_by(path: p.to_s) }
  #           payload[:concept_count] = created.size
  #           created
  #         end
  #       end
  #     end
  #   end
  #
  # The emitted event name follows one convention across the whole family:
  #
  #     <component>.<class>.<verb>        e.g. "cnfs_okf.bundle.create"
  #
  # - <component> is CnfsSupport.component_tag(self.class.name) => "cnfs_okf",
  #   the SAME identifier CnfsSupport::Logging tags with. So a gem's logs and its
  #   traces share one name by construction and can never drift.
  # - <class> is the demodulized class name, underscored => "bundle".
  # - <verb> is the argument the caller passes (:create, :render, ...). It is
  #   explicit rather than sniffed from `caller`, because inside AR callbacks and
  #   blocks the calling frame's label is unreliable (it reads "block in ..."),
  #   which is exactly the case we instrument first.
  #
  # This module knows NOTHING about OpenTelemetry. It only produces well-formed
  # notifications. If cnfs_telemetry is installed in the host, it subscribes to
  # the <component> prefix and turns each event into a span whose tracer name is
  # that same <component>. If it is not installed, these are cheap no-op
  # notifications.
  module Instrumentable
    extend ActiveSupport::Concern

    # Instance entry point. Composes the event name from this instance's class
    # and instruments the block (whose duration becomes the span's duration).
    def instrument(verb, **payload, &block)
      name = CnfsSupport::Instrumentable.event_name(self.class.name, verb)
      ActiveSupport::Notifications.instrument(name, **payload, &block)
    end

    class_methods do
      # Class-level entry point, for instrumenting class methods / lifecycle work
      # that has no instance yet. Uses the class's own name as the subject.
      def instrument(verb, **payload, &block)
        name = CnfsSupport::Instrumentable.event_name(self.name, verb)
        ActiveSupport::Notifications.instrument(name, **payload, &block)
      end
    end

    # Compose "<component>.<class>.<verb>" from a fully-qualified class name.
    # Reuses component_tag for the <component> half so the identifier matches the
    # logging tag exactly.
    #
    #   event_name("CnfsOkf::Bundle", :create) => "cnfs_okf.bundle.create"
    #   event_name("CnfsOkf::Bundle", "create") => "cnfs_okf.bundle.create"
    def self.event_name(class_name, verb)
      component = CnfsSupport.component_tag(class_name)
      subject   = class_name.to_s.demodulize.underscore
      subject   = "object" if subject.empty?
      "#{component}.#{subject}.#{verb}"
    end
  end
end
