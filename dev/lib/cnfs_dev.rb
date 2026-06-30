require_relative "cnfs_dev/version"
require_relative "cnfs_dev/railtie"

module CnfsDev
  # Console/Pry integration is loaded lazily by the Railtie's `console` block;
  # see lib/cnfs_dev/pry_ext.rb. The Railtie itself is only defined when
  # Rails is present (see railtie.rb), so requiring this gem outside Rails is
  # safe.
end
