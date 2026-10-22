module Partitia
  module Iam
    # Seeds identity into a freshly provisioned database. Registered into
    # Partitia::Tenanted.after_provision (guarded) by the engine, and run INSIDE the new
    # database's tenant context (Plan 001's contract). Inert in single-tenant apps
    # (never registered when Partitia::Tenanted is absent).
    #
    # ONE code path for both planes (ADR 0003 §2): `context` responds to #name and
    # #owner_email — a Tenant for tenant provisioning, Partitia::Tenanted's platform
    # struct for the reserved-database run. Both seed the Account singleton plus a
    # root principal (the tenant owner / the platform owner) with a bootstrap
    # token. A raise propagates and aborts provisioning (deliberate).
    class TenantSeeder
      include Partitia::Support::Instrumentable
      include Partitia::Support::Logging

      class << self
        # Surfaces the most recently issued root bootstrap token to the
        # provisioning caller. Provisioning runs synchronously inside
        # create_tenant, so the caller reads this immediately afterward.
        # Spike-simple: a concurrent provisioner would race here — swap for a
        # per-call sink if that ever becomes real.
        attr_accessor :last_bootstrap_token

        # Provisioning-hook span (iam.tenant_seeder.seed): seeds the Account
        # singleton + root principal into a freshly provisioned database. Nests
        # under partitia_tenanted.provisioning.run.
        def call(context)
          instrument(:seed, account: context.name) do
            Partitia::Iam::Account.instance(name: context.name)

            root = Partitia::Iam::HumanPrincipal.create!(
              root: true,
              name: context.owner_email,
              email: context.owner_email
            )
            self.last_bootstrap_token = root.issue_link_token!
            # Account name is fine; log the root id, not the seeded email.
            logger.info { "seed: account=#{context.name} root principal seeded id=#{root.id}" }
          rescue => e
            # A raise aborts provisioning (deliberate) — leave a line before it
            # propagates. Class only; the message may carry the seeded email.
            logger.warn { "seed aborted: #{e.class}" }
            raise
          end
        end
      end
    end
  end
end
