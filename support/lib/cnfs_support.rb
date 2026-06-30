require_relative "cnfs_support/version"
require_relative "cnfs_support/railtie" if defined?(Rails::Railtie)

# CnfsSupport is the lean foundation gem for the CNFS family — the active_support
# analogue. It carries dependency-light primitives that other CNFS gems and the
# apps can depend on freely, in any environment.
module CnfsSupport
  # Any rails plugin can register here
  # Any migrations or global migrations will be registered here
  def self.plugins
    @plugins ||= Set.new
  end

  def self.migrations_paths
    # NOTE: This stirng needs to be exactly "db/migrate", not Rails.root.join like the engine
    # Path needs to be relative in order for the rails built-in rake tasks to find it properly
    @migrations_paths ||= ["db/migrate"]
  end

  def self.migrations
    migrations_paths.each_with_object([]) do |path, ary|
      ary.concat(Pathname.new(path).children.collect(&:to_s))
    end
  end
end
