require_relative "lib/partitia/tenanted/version"

Gem::Specification.new do |spec|
  spec.name        = "partitia-tenanted"
  spec.version     = Partitia::Tenanted::VERSION
  spec.authors     = [ "Robert Roach" ]
  spec.email       = [ "rjayroach@gmail.com" ]
  spec.homepage    = "TODO"
  spec.summary     = "Multi-tenant support for CNFS Rails apps (database-per-tenant)."
  spec.description = "Provides the tenant layer for CNFS apps built on " \
                    "activerecord-tenanted: a global Tenant registry, tenant " \
                    "provisioning, the reserved platform database, request tenant " \
                    "resolution, tenant-aware MVC (with eject generators) and " \
                    "migration status across tenant databases."
  spec.license     = "MIT"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the "allowed_push_host"
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "TODO: Put your gem's public repo URL here."
  spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."

  spec.required_ruby_version = ">= 3.2.0"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 8.1.3"

  # The per-tenant database engine this gem builds on.
  spec.add_dependency "activerecord-tenanted"

  # Lean CNFS foundation: provides the pre-boot tenant migration-path registry
  # that this engine registers its db/migrate path with.
  spec.add_dependency "partitia-support"

  # This engine ships Tailwind-styled tenant/account views.
  spec.add_dependency "tailwindcss-rails"

  # NOTE: partitia-dev is intentionally NOT a dependency. The tenant-aware Pry
  # console helpers activate only when partitia-dev happens to be loaded
  # (development/test), detected via defined?(Partitia::Dev). Multi-tenancy and
  # console tooling are orthogonal; an app can use one without the other.
end
