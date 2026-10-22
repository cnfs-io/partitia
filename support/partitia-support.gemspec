require_relative "lib/partitia/support/version"

Gem::Specification.new do |spec|
  spec.name        = "partitia-support"
  spec.version     = Partitia::Support::VERSION
  spec.authors     = [ "Robert Roach" ]
  spec.email       = [ "rjayroach@gmail.com" ]
  spec.homepage    = "TODO"
  spec.summary     = "Lean foundation primitives for the CNFS gem family."
  spec.description = "The active_support analogue for CNFS: dependency-light, " \
                    "environment-agnostic primitives (e.g. the tenant migration-path " \
                    "registry) that other CNFS gems and apps can depend on freely. " \
                    "Console/debugging tooling lives separately in partitia-dev."
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

  spec.add_dependency "activesupport", ">= 8.1.3"
  # anyway_config fits the charter: environment-agnostic, no Rails dependency,
  # usable pre-boot (its very purpose is resolving config before/without Rails).
  # Provides the Partitia::Support::Config base class every CNFS gem derives its
  # config classes from (YAML -> credentials -> ENV resolution, typed attrs).
  spec.add_dependency "anyway_config", "~> 2.7"
  # mixlib-shellout backs Partitia::Support::Shell — the one subprocess boundary every
  # CNFS gem shells out through. A real, actively-maintained runtime dep on
  # purpose: it owns the platform-specific process handling (unix.rb/windows.rb,
  # FFI, child-process termination on timeout) we deliberately do NOT vendor. The
  # thin adapter in lib/partitia/support/shell.rb applies our conventions on top.
  spec.add_dependency "mixlib-shellout", ">= 3.3"
  # Intentionally NO runtime dependency on Rails. The core value (the tenant
  # migration-path registry) is plain Ruby and must be usable pre-boot, before
  # Rails loads. The Railtie is defined only when Rails is already present
  # (see lib/partitia/support/railtie.rb), so a hard Rails runtime dep is both
  # unnecessary and would wrongly force Rails into non-Rails consumers.
  spec.add_development_dependency "rails", ">= 8.1.3"
end
