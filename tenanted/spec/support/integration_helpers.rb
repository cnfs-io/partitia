module IntegrationHelpers
  # Re-establish the wiring that spec/support/tenancy.rb's per-example reset
  # clears — iam's after_provision seeder registration and the platform console
  # guard — and stub the IdP HTTP surface. Called from an integration example
  # group's `before`, which runs AFTER the global tenancy reset.
  def wire_integration!
    Partitia::Tenanted.after_provision << ->(context) { Partitia::Iam::TenantSeeder.call(context) }
    Partitia::Tenanted.platform_console_guard = IDENTITY_CONSOLE_GUARD
    stub_oidc_discovery
  end

  def provision_platform!(owner_email: "owner@platform.test")
    Partitia::Tenanted.provision_platform!(owner_email: owner_email)
  end

  def handle_for(subdomain)
    Partitia::Tenanted::Tenant.find_by(subdomain: subdomain).handle
  end

  # A tenant registry row; its after_create provisions the tenant DB and runs the
  # seeder (Account + root + bootstrap token) inside it.
  def create_tenant!(subdomain:, owner_email: "owner@#{subdomain}.test", name: nil)
    Partitia::Tenanted::Tenant.create!(name: name || subdomain.capitalize, subdomain: subdomain, owner_email: owner_email)
  end

  # An App Admin (a NON-root principal) seeded explicitly into the reserved DB,
  # with a bootstrap/invite token — App Admins are never auto-seeded (ADR 0004).
  def seed_app_admin!(email: "admin@platform.test")
    Partitia::Tenanted.with_platform do
      admin = Partitia::Iam::HumanPrincipal.create!(name: email, email: email)
      [ admin, admin.issue_link_token! ]
    end
  end

  # The bootstrap token the seeder surfaced for the most recently provisioned DB.
  def last_bootstrap_token
    Partitia::Iam::TenantSeeder.last_bootstrap_token
  end

  # Drive the full OIDC round-trip and stop once the callback has run. The result
  # is the callback response. mode: :invite_only (default) | :jit | :platform.
  def oidc_login(host:, subject: "idp-sub-1", email: "user@example.com", name: "User",
                 link_token: nil, mode: :invite_only)
    host! host

    entry =
      case mode
      when :jit      then "/app/login"
      when :platform then "/platform/login"
      else                "/auth/login"
      end

    get entry, params: { link_token: link_token }.compact
    while response.redirect? && URI(response.location).path.start_with?("/app", "/platform", "/auth/login")
      follow_redirect!
    end

    query = Rack::Utils.parse_query(URI(response.location).query)
    stub_token_endpoint(id_token: id_token(nonce: query["nonce"], sub: subject, email: email, name: name))

    get "/auth/callback", params: { code: "auth-code", state: query["state"] }
  end
end

RSpec.configure do |config|
  config.include IntegrationHelpers, type: :request
end
