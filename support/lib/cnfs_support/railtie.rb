module CnfsSupport
  class Railtie < ::Rails::Railtie
    initializer :set_migrations_paths do |app|
      CnfsSupport.set_migrations_paths_from(Rails)
      CnfsSupport.plugins.each do |plugin|
        raise "#{plugin} must be a Rails Engine" unless plugin.is_a?(Class) && plugin < ::Rails::Engine

        CnfsSupport.set_migrations_paths_from(plugin)
      end
    end

    # Registering as a CnfsSupport plugin is the declaration that a gem wants
    # CnfsSupport's model functionality, so transparently mix CnfsSupport::Model
    # into each registered engine's ApplicationRecord. Every model in that gem
    # then gets `logger` + `instrument` for free, with no per-gem include.
    #
    # Mirrors the plugin walk cnfs_tenanted uses for subtenant_of
    # (cnfs_tenanted/engine.rb). Runs in `to_prepare` (not `after_initialize`) so
    # the include survives dev code reloads, which redefine the ApplicationRecord
    # constant. `include` is idempotent, so re-running is safe and a gem that
    # still includes Model by hand keeps working.
    config.to_prepare do
      CnfsSupport.plugins.each do |plugin|
        next unless defined?(plugin.module_parent::ApplicationRecord)

        ar = plugin.module_parent::ApplicationRecord
        ar.include(CnfsSupport::Model) unless ar.include?(CnfsSupport::Model)
      end
    end
  end
end
