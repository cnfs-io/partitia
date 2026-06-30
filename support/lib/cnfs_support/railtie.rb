module CnfsSupport
  class Railtie < ::Rails::Railtie
    initializer :process_plugins do |app|
      CnfsSupport.plugins.each do |plugin|
        next unless plugin.is_a?(Class) && plugin < ::Rails::Engine

        next unless app.config.x.migrations_in_place == true

        path = plugin.root.join("db/migrate")
        CnfsSupport.migrations_paths << path.to_s if path.exist?
      end
    end

    # initializer :append_migrations_paths do |app|
    #   if app.config.x.migrations_in_place == true
    #     CnfsSupport.migrations_paths.uniq.each do |path|
    #       app.config.paths["db/migrate"] << path
    #     end
    #   end
    # end
  end
end
