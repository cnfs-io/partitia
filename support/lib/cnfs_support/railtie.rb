module CnfsSupport
  class Railtie < ::Rails::Railtie
    initializer :set_migrations_paths do |app|
      CnfsSupport.set_migrations_paths_from(Rails)
      CnfsSupport.plugins.each do |plugin|
        raise "#{plugin} must be a Rails Engine" unless plugin.is_a?(Class) && plugin < ::Rails::Engine

        CnfsSupport.set_migrations_paths_from(plugin)
      end
    end

    # Make `logger` + `instrument` universally available across the whole
    # application — every registered gem AND the host app — so no class ever
    # needs a manual include to log or instrument. This is the entire point of
    # cnfs_support owning these: DRYness and consistency, application-wide.
    #
    # Two base classes, two concern sets:
    #   ApplicationRecord     <- Logging + Instrumentable  (logger + instrument)
    #   ApplicationController  <- Logging                   (logger only)
    #
    # Controllers get Logging but NOT instrument: Rails already instruments
    # controller actions natively (process_action.action_controller), and OTel's
    # Rails instrumentation covers request tracing, so auto-mixing `instrument`
    # onto every controller would be redundant surface and risk double-tracing.
    # Logging on controllers, by contrast, is plainly useful and has no native
    # equivalent under the CNFS tag scheme.
    #
    # Both run in `to_prepare` (not `after_initialize`) so the includes survive
    # dev code reloads, which redefine the ApplicationRecord/ApplicationController
    # constants. `include` is idempotent (guarded by `include?`), so re-running is
    # safe and a class that still includes a concern by hand keeps working.
    #
    # Mirrors the plugin walk cnfs_tenanted uses for subtenant_of
    # (cnfs_tenanted/engine.rb), extended to also reach the host's top-level
    # ApplicationRecord/ApplicationController — the host is not in
    # CnfsSupport.plugins (that set is engines only), so it is injected by name.
    config.to_prepare do
      CnfsSupport::Railtie.inject_model_functionality
      CnfsSupport::Railtie.inject_controller_logging
    end

    class << self
      # Mix Logging + Instrumentable into every plugin's ApplicationRecord and
      # the host's top-level ApplicationRecord. Every model — gem or host — then
      # has `logger` + `instrument` with no per-model include. (These two direct
      # includes ARE what a model needs; there is no bundling meta-concern —
      # this railtie is the single place the pair is applied.)
      def inject_model_functionality
        application_record_classes.each do |ar|
          ar.include(CnfsSupport::Logging) unless ar.include?(CnfsSupport::Logging)
          ar.include(CnfsSupport::Instrumentable) unless ar.include?(CnfsSupport::Instrumentable)
        end
      end

      # Mix CnfsSupport::Logging into every plugin's ApplicationController and the
      # host's top-level ApplicationController. Every controller — gem or host —
      # then has `logger`. This is what lets a gem CONCERN mixed into the host's
      # controller (e.g. Iam::Authenticatable) find `logger` present: the method
      # lives on the host ApplicationController it was mixed into. (A concern that
      # wants its OWN gem's log tag, rather than the host controller's, still
      # derives the tag from a fixed constant name — see Iam::Authenticatable —
      # because inside the concern `self` is the host controller.)
      def inject_controller_logging
        application_controller_classes.each do |ac|
          ac.include(CnfsSupport::Logging) unless ac.include?(CnfsSupport::Logging)
        end
      end

      private

      # Each plugin's namespaced ApplicationRecord (CnfsOkf::ApplicationRecord,
      # …) plus the host's top-level ::ApplicationRecord, skipping any that are
      # not defined/loaded yet (Zeitwerk-safe: never force a constant to load).
      def application_record_classes
        base_classes(:ApplicationRecord)
      end

      def application_controller_classes
        base_classes(:ApplicationController)
      end

      # Collect the named base class from every plugin's namespace and from the
      # top level (the host). `defined?` on the fully-qualified path avoids
      # force-autoloading a constant that isn't ready.
      def base_classes(const_name)
        namespaces = CnfsSupport.plugins.map(&:module_parent)
        namespaces << Object # top-level host constants (::ApplicationRecord etc.)

        namespaces.filter_map do |ns|
          next unless ns.const_defined?(const_name, false)

          ns.const_get(const_name, false)
        end.uniq
      end
    end
  end
end
