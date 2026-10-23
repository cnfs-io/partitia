module Partitia
  module Iam
    # The first sign-in (D6): within the CURRENT database, the root principal and,
    # while root has no identity link yet, a fresh bootstrap link token for it.
    #
    # The root claims itself with an :invite_only sign-in carrying that token
    # (cognito's /auth/login?link_token=…): Resolution binds the IdP identity to
    # root and consumes the token. Afterwards root signs in like anyone known, and
    # no token is issued here again (RootRecovery resets a locked-out root).
    #
    # A database with no root yet (a single-tenant app: nothing provisions it) is
    # seeded first, through the same TenantSeeder tenants and the platform use
    # (the Account singleton and root). Each call while unclaimed issues a new
    # token; the previous one stops working. No tenancy logic here: the caller
    # selects the database (the partitia:iam:bootstrap task does).
    class Bootstrap
      include Partitia::Support::Instrumentable
      include Partitia::Support::Logging

      Context = Struct.new(:name, :owner_email)

      # token is the plaintext (returned once), nil when root is already claimed
      Result = Struct.new(:root, :token, keyword_init: true) do
        def claimed? = token.nil?
      end

      def self.call(name:, owner_email:)
        instrument(:call) do |event|
          root = Partitia::Iam::HumanPrincipal.find_by(root: true)
          if root.nil?
            Partitia::Iam::TenantSeeder.call(Context.new(name, owner_email))
            event[:outcome] = "seeded"
            next Result.new(root: Partitia::Iam::HumanPrincipal.find_by!(root: true),
                            token: Partitia::Iam::TenantSeeder.last_bootstrap_token)
          end

          if root.identity_links.exists?
            event[:outcome] = "claimed"
            logger.info { "bootstrap: root principal id=#{root.id} is claimed; no token issued" }
            next Result.new(root: root)
          end

          event[:outcome] = "reissued"
          Result.new(root: root, token: root.issue_link_token!)
        end
      end
    end
  end
end
