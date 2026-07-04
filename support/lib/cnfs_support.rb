require_relative "cnfs_support/version"
require_relative "cnfs_support/logging"
require_relative "cnfs_support/railtie" if defined?(Rails::Railtie)
require "active_support/core_ext/string/inflections"

# CnfsSupport is the lean foundation gem for the CNFS family — the active_support
# analogue. It carries dependency-light primitives that other CNFS gems and the
# apps can depend on freely, in any environment.
module CnfsSupport
  # Derive a component tag from a fully-qualified class/module name: the first
  # `::`-split segment, downcased. `"Okf::Button"` => `"okf"`. Anonymous or
  # nameless classes (name is nil/empty) fall back to `"cnfs"`.
  #
  # The Logging mixin keys off this rule for its tag. Telemetry (in the separate
  # cnfs_telemetry gem) derives the same rule from notification names, so a gem's
  # log tags and trace instrumentation-library names stay aligned.
  def self.component_tag(name)
    segment = name.to_s.deconstantize.underscore
    segment.empty? ? "cnfs" : segment
  end

  # Any rails plugin can register here
  # Any migrations or global migrations will be registered here
  def self.plugins
    @plugins ||= Set.new
  end

  # There are two ways migrations paths are set
  # 1. The application's database.yml DOES NOT declare migrations_paths for a database (default)
  #    In this case Rails will apply the value of app.config.paths['db/migrate']
  #
  # 2. The application's database.yml declares migrations_paths for a database
  #    In that case it can either
  #    1. Hard code it
  #         migrations_paths = ["path/1", "path/2"]
  #    2. Use CnfsSupport's migration_paths:
  #         migrations_paths = <% CnfsSupport.migration_paths[:primary] %>
  #
  # CnfsSupport migrations_paths will include paths to all engine's migrations paths
  #   so it is assumed that when using this in database.yml that you are NOT copying
  #   migrations from engines into the app.
  # If the desired workflow is to copy from engines then just hardcode the migrations_paths
  #   or don't declare it and Rails will work as per default
  def self.migrations_paths_for
    @migrations_paths_for ||= { primary: "db/migrate" }
  end

  def self.migrations_paths
    @migrations_paths ||= {}
  end

  def self.set_migrations_paths_from(plugin)
    migrations_paths_for.each do |key, search_path|
      migrations_paths[key] ||= []

      path = plugin.root.join(search_path)
      migrations_paths[key] << path.to_s if path.exist?
    end
  end

  def self.migrations
    migrations_paths.each_with_object([]) do |(key, paths), ary|
      paths.each do |path|
        path = Pathname.new(path)
        ary.concat(path.children.collect(&:to_s)) if path.exist?
      end
    end
  end
end
