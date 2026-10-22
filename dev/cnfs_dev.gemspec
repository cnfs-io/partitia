require_relative "lib/cnfs_dev/version"

Gem::Specification.new do |spec|
  spec.name        = "cnfs_dev"
  spec.version     = CnfsDev::VERSION
  spec.authors     = [ "Robert Roach" ]
  spec.email       = [ "rjayroach@gmail.com" ]
  spec.homepage    = "TODO"
  spec.summary     = "TODO: Summary of CnfsDev."
  spec.description = "TODO: Description of CnfsDev."
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

  # Console / debugging tooling. Providing a consistent Pry-based console
  # experience across CNFS apps is a core purpose of this gem, so these are
  # runtime dependencies rather than development-only.
  spec.add_dependency "pry", ">= 0.16"
  spec.add_dependency "pry-rails", "~> 0.3"
  spec.add_dependency "pry-byebug", "~> 3.12"
  spec.add_dependency "amazing_print", ">= 2", "< 4"
end
