module Partitia
  module Iam
    # A human user principal. URN resource_type "user" (AWS-shaped), rather than
    # the demodulized class name.
    #
    # Humans are the only principals that can be `root` (the distinguished
    # per-database principal, ADR 0004) and the only ones that carry IdP identity
    # links and bootstrap/invite tokens — machines authenticate via credentials.
    class HumanPrincipal < Principal
      urn_resource_type "user"

      has_many :identity_links,
               class_name: "Partitia::Iam::IdentityLink",
               foreign_key: :principal_id,
               dependent: :destroy

      # At most one root per database (ADR 0004): mirrors the partial unique index
      # for a friendly error and defense in depth.
      validate :single_root, if: :root?
      # Root is a one-way flag — it cannot be demoted through normal update paths.
      validate :root_not_demoted, on: :update
      # ...and a root principal cannot be destroyed. Lockout recovery resets its
      # identity links instead (see Partitia::Iam::RootRecovery), it never deletes root.
      before_destroy :prevent_root_destroy

      DEFAULT_LINK_TOKEN_TTL = 7.days

      # Issue a one-time bootstrap/invite token (ADR 0004): a high-entropy secret
      # whose HMAC digest is stored (never the plaintext), returned once here.
      # Reuses the Partitia::Iam::Secret primitives.
      def issue_link_token!(ttl: DEFAULT_LINK_TOKEN_TTL)
        # Bootstrap/invite token issuance span (iam.human_principal.issue_link_token):
        # the plaintext is never put on the payload.
        instrument(:issue_link_token, root: root?) do
          token = Partitia::Iam::Secret.generate
          update!(link_token_digest: Partitia::Iam::Secret.digest(token), link_token_expires_at: ttl.from_now)
          # TTL/expiry are fine to log; the plaintext token is never logged.
          logger.info { "link token issued for principal id=#{id} root=#{root?} ttl=#{ttl.inspect}" }
          token
        end
      end

      # The human principal holding a matching, UNEXPIRED link token, or nil.
      # Lookup is by HMAC digest (deterministic; the plaintext token is never
      # stored and cannot be derived from the digest).
      def self.find_by_link_token(plaintext)
        return nil if plaintext.to_s.empty?

        where(link_token_expires_at: Time.current..)
          .find_by(link_token_digest: Partitia::Iam::Secret.digest(plaintext))
          .tap { |principal| logger.debug { "find_by_link_token: #{principal ? 'hit' : 'miss'}" } }
      end

      # Single-use: clear the token once consumed.
      def consume_link_token!
        instrument(:consume_link_token) do
          update!(link_token_digest: nil, link_token_expires_at: nil)
          logger.info { "link token consumed for principal id=#{id}" }
        end
      end

      private

      def single_root
        scope = Partitia::Iam::Principal.where(root: true)
        scope = scope.where.not(id: id) if persisted?
        errors.add(:root, I18n.t("partitia_iam.principal.errors.duplicate_root")) if scope.exists?
      end

      def root_not_demoted
        return unless will_save_change_to_root? && root_in_database && !root

        errors.add(:root, I18n.t("partitia_iam.principal.errors.root_not_demotable"))
      end

      def prevent_root_destroy
        return unless root?

        raise ActiveRecord::ReadOnlyRecord, I18n.t("partitia_iam.principal.errors.root_undestroyable")
      end
    end
  end
end
