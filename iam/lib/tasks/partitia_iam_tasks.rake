# The first sign-in (D6). Prints, on stdout, ROOT=claimed or ROOT=unclaimed and
# LINK_TOKEN=<token>: sign in once as root with <cognito mount>/login?link_token=<token>
# (single use, 7 days; each run issues a new one). The token is a secret: don't paste it
# anywhere shared.
namespace :partitia do
  namespace :iam do
    desc "First sign-in: the root principal's bootstrap link token while root is unclaimed " \
         "(TENANT=<subdomain> or TENANT=platform with partitia-tenanted; OWNER_EMAIL seeds a single-tenant root)"
    task bootstrap: :environment do
      app = Rails.application.class.module_parent_name
      bootstrap = lambda do |name, where|
        owner = ENV["OWNER_EMAIL"].presence || "owner@#{app.underscore.dasherize}.test"
        result = Partitia::Iam::Bootstrap.call(name: name, owner_email: owner)
        if result.claimed?
          puts "ROOT=claimed"
          warn "partitia:iam:bootstrap: root (#{result.root.email}) in #{where} is claimed: it signs in " \
               "with no token. Locked out: Partitia::Iam::RootRecovery.reset! in that database."
        else
          puts "ROOT=unclaimed", "LINK_TOKEN=#{result.token}"
          warn "partitia:iam:bootstrap: root (#{result.root.email}) in #{where} is unclaimed. Sign in once " \
               "with <cognito mount>/login?link_token=<LINK_TOKEN> (e.g. /auth/login?link_token=…): " \
               "single use, valid 7 days; the identity you sign in with becomes root."
        end
      end

      if defined?(Partitia::Tenanted)
        subdomain = ENV["TENANT"].to_s
        abort "partitia:iam:bootstrap: a multi-tenant app: TENANT=<subdomain> (or TENANT=platform)" if subdomain.empty?
        if subdomain == Partitia::Tenanted::RESERVED_HANDLE
          Partitia::Tenanted.with_platform { bootstrap.call("Platform", "the platform database") }
        else
          tenant = Partitia::Tenanted::Tenant.find_by(subdomain: subdomain) or
            abort "partitia:iam:bootstrap: no tenant #{subdomain.inspect}"
          ::ApplicationRecord.with_tenant(tenant.handle) { bootstrap.call(tenant.name, "tenant #{subdomain}") }
        end
      else
        bootstrap.call(app, "the app's database")
      end
    end
  end
end
