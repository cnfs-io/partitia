require_relative "lib/partitia/iam/version"

Gem::Specification.new do |spec|
  spec.name        = "partitia-iam"
  spec.version     = Partitia::Iam::VERSION
  spec.authors     = [ "Robert Roach" ]
  spec.email       = [ "rjayroach@gmail.com" ]
  spec.homepage    = "TODO"
  spec.summary     = "TODO: Summary of Partitia::Iam."
  spec.description = "TODO: Description of Partitia::Iam."
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.2"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the "allowed_push_host"
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "TODO: Put your gem's public repo URL here."
  spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 8.1.3"
  # Config base (Partitia::Support::Config) + the migration-path plugin registry.
  spec.add_dependency "partitia-support"
  # Optional, detected at runtime with defined? and deliberately NOT declared:
  # partitia-tenanted (after_provision seeding, tenant account handle) and
  # partitia-dev (console shortcuts).
  # Encrypted attributes on IAM-owned models (credentials, tokens). The gem
  # declares has_encrypted; the host app owns the master key (LockboxConfig
  # + initializer), since Lockbox.master_key is process-global.
  spec.add_dependency "lockbox", "~> 2.0"
  spec.add_dependency "turbo-rails"
  spec.add_dependency "stimulus-rails"
  spec.add_dependency "importmap-rails"
  spec.add_dependency "tailwindcss-rails"
end
