require "rails_helper"

# Opt-in only — excluded from the default run (see rails_helper's
# filter_run_excluding :authentik). Exercises real OIDC discovery against a live
# Authentik container started via `bin/authentik up`. Run with:
#
#   AUTHENTIK_ISSUER=http://localhost:9000/application/o/<slug>/ \
#     bundle exec rspec --tag authentik
RSpec.describe "Authentik (live)", :authentik do
  it "discovers the OIDC configuration from a running container" do
    WebMock.allow_net_connect!
    provider = Partitia::Cognito::Providers::Authentik.new(
      issuer: ENV.fetch("AUTHENTIK_ISSUER"),
      client_id: ENV.fetch("AUTHENTIK_CLIENT_ID", "test")
    )
    expect { provider.send(:discovery) }.not_to raise_error
  ensure
    WebMock.disable_net_connect!
  end
end
