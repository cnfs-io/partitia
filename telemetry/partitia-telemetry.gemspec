require_relative "lib/partitia/telemetry/version"

Gem::Specification.new do |spec|
  spec.name        = "partitia-telemetry"
  spec.version     = Partitia::Telemetry::VERSION
  spec.authors     = [ "Robert Roach" ]
  spec.email       = [ "rjayroach@gmail.com" ]
  spec.homepage    = "TODO"
  spec.summary     = "ActiveSupport::Notifications -> OpenTelemetry span bridge for the CNFS gem family."
  spec.description = "Subscribes to partitia-prefixed ActiveSupport::Notifications events " \
                    "and translates them into OpenTelemetry spans. Depends on the OTel " \
                    "API only — no SDK, no exporters. Stays a no-op until a host app " \
                    "installs and configures the SDK (via the install generator)."
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

  # The bridge depends on the OpenTelemetry API ONLY — never the SDK. The API
  # ships a no-op tracer provider, so every span the subscriber opens is free
  # until a host installs and configures the SDK (see the install generator).
  # semantic_conventions supplies standard attribute-key constants so spans
  # render correctly in Tempo/Grafana.
  spec.add_dependency "opentelemetry-api", "~> 1.1"
  spec.add_dependency "opentelemetry-semantic_conventions", "~> 1.37"

  # ActiveSupport::Notifications is the emit-side contract every CNFS gem uses.
  # This is the one heavier dep, but it is the whole point of the bridge and is
  # always present in a Rails host. Pinned to the Rails line the family targets.
  spec.add_dependency "activesupport", ">= 8.1.3"

  spec.add_development_dependency "rails", ">= 8.1.3"
end
