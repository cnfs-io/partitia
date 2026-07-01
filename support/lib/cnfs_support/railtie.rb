module CnfsSupport
  class Railtie < ::Rails::Railtie
    initializer :set_migrations_paths do |app|
      CnfsSupport.set_migrations_paths_from(Rails)
      CnfsSupport.plugins.each do |plugin|
        raise "#{plugin} must be a Rails Engine" unless plugin.is_a?(Class) && plugin < ::Rails::Engine

        CnfsSupport.set_migrations_paths_from(plugin)
      end
    end
  end
end
