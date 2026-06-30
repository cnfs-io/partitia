module CnfsTenanted
  class Engine < ::Rails::Engine
    CnfsSupport.plugins << self

    # Process registered plugins
    # If app.config.x.migraitons_in_place is true and <plugin_root>/db/global_migrate exists
    # then add it to the global_migrations_paths which is ERB'd in the app's config/database.yml
    initializer :process_plugins do |app|
      CnfsSupport.plugins.each do |plugin|
        next unless plugin.is_a?(Class) && plugin < ::Rails::Engine

        next unless app.config.x.migrations_in_place == true

        path = plugin.root.join("db/global_migrate")
        CnfsTenanted.global_migrations_paths << path.to_s if path.exist?
      end
      path = Rails.root.join("db/global_migrate")
      CnfsTenanted.global_migrations_paths << path.to_s if path.exist?
    end

    # Ensure each registered gem's models that are not explicit subclasses of GlobalRecord
    # are subtenant classes
    config.after_initialize do
      CnfsSupport.plugins.each do |plugin|
        next unless defined?(plugin.module_parent::ApplicationRecord)

        ar = plugin.module_parent::ApplicationRecord
        ar.subtenant_of("ApplicationRecord") if ar.respond_to?(:subtenant_of)
      end
    end

    # Ship Tailwind-styled views; scaffolding/generators default accordingly.
    config.generators do |g|
      g.template_engine :tailwindcss
    end

    # Make the rake-task helper available when tasks load.
    rake_tasks do
      require "cnfs_tenanted/migration_status"
    end

    # Contribute tenant-aware Pry console helpers, but only when a console
    # session starts (never in web/job processes) and only if cnfs_dev is
    # present to host them. See CnfsTenanted::PryConsole.
    console do
      require "cnfs_tenanted/pry_console"
      CnfsTenanted::PryConsole.install!
    end
  end
end
