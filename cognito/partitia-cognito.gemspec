require_relative "lib/partitia/cognito/version"

Gem::Specification.new do |spec|
  spec.name        = "partitia-cognito"
  spec.version     = Partitia::Cognito::VERSION
  spec.authors     = [ "Robert Roach" ]
  spec.email       = [ "rjayroach@gmail.com" ]
  spec.homepage    = "TODO"
  spec.summary     = "TODO: Summary of Partitia::Cognito."
  spec.description = "TODO: Description of Partitia::Cognito."
  spec.license     = "MIT"

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
  # Config base (Partitia::Support::Config), Logging and Instrumentable.
  spec.add_dependency "partitia-support"
  # partitia-iam is NOT a dependency: the host wires identity_resolver to
  # Partitia::Iam::Resolution (ADR 0004); the broker never references Iam.
  # OIDC/JWT verification (ID-token signature, iss/aud/exp/nonce). Do not
  # hand-roll JWT/JWKS validation (Plan 003 WS2).
  spec.add_dependency "jwt"
end
