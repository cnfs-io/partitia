module Iam
  # Root lockout recovery (ADR 0004): within the CURRENT database context, drop
  # the root principal's identity links and reissue a bootstrap token (returned
  # once). No cross-plane logic here — the platform console composes this with
  # `with_tenant(handle)` to reach a specific tenant (ADR 0003 §7).
  class RootRecovery
    include CnfsSupport::Instrumentable
    include CnfsSupport::Logging

    def self.reset!
      # Security-sensitive: root lockout recovery is always traced AND logged
      # (iam.root_recovery.reset). It drops root's identity links and reissues a
      # bootstrap token — an operation an operator should always be able to audit.
      instrument(:reset) do
        root = Iam::HumanPrincipal.find_by(root: true)
        raise ActiveRecord::RecordNotFound, "no root principal in this database" unless root

        logger.warn { "root recovery: resetting identity links for principal #{root.id}" }
        root.identity_links.destroy_all
        root.issue_link_token!
      end
    end
  end
end
