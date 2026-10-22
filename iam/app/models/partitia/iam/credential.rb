module Partitia
  module Iam
    # A long-lived credential owned by a Principal (ADR 0002 §3, ADR 0003
    # Decision 1). Concept ported from the 2019 Ros::Credential (polymorphic owner,
    # generate-on-create, token accessor) but rewritten for 2026: a plaintext
    # self-describing AccessKey ID (split-to-parse) + an HMAC-SHA256 secret digest.
    # NO hashids, NO bcrypt.
    #
    # The plaintext secret is available ONCE, on the freshly-created in-memory
    # object (via #secret), and is never persisted or re-derivable.
    class Credential < ApplicationRecord
      include Partitia::Iam::HasUrn

      belongs_to :owner, polymorphic: true

      validates :access_key_id, presence: true, uniqueness: true
      validates :secret_digest, presence: true
      # Root holds no access keys — it creates machine principals, which hold the
      # keys (ADR 0004). Enforced here so no code path can mint one for root.
      validate :owner_is_not_root

      before_validation :issue_credentials, on: :create

      # The URN resource_id is the access key id, not the row id (ADR 0002 §4).
      urn_id :access_key_id
      urn_resource_type "access_key"

      # Authenticate a (access_key_id, plaintext_secret) pair. Malformed keys are
      # rejected on shape/checksum before any DB or HMAC work. Returns the owning
      # principal on success, nil otherwise. Constant-time secret comparison.
      def self.authenticate(access_key_id, plaintext_secret)
        # The machine-request auth span (iam.credential.authenticate): the highest
        # frequency auth path. Records only the outcome — never the key or secret.
        instrument(:authenticate) do |event|
          logger.debug { "authenticate: begin" }
          unless Partitia::Iam::AccessKeyId.valid?(access_key_id)
            event[:outcome] = "malformed"
            logger.warn { "credential auth malformed" }
            next nil
          end

          credential = find_by(access_key_id: access_key_id)
          unless credential&.verify_secret(plaintext_secret)
            event[:outcome] = "rejected"
            logger.warn { "credential auth rejected" }
            next nil
          end

          event[:outcome] = "authenticated"
          logger.debug { "authenticate: authenticated owner id=#{credential.owner_id}" }
          credential.owner
        end
      end

      # Plaintext secret, present only immediately after generation (shown once).
      attr_reader :secret

      def verify_secret(plaintext_secret)
        Partitia::Iam::Secret.verify(plaintext_secret, secret_digest)
      end

      # The plaintext is a one-time, generation-only artifact; drop it on reload so
      # even the originating object cannot surface it after a round-trip.
      def reload(*)
        @secret = nil
        super
      end

      private

      def issue_credentials
        # Credential/token issuance span (partitia_iam.credential.issue): mints the
        # self-describing access-key id + HMAC secret on create. Carries a bounded
        # owner_type dimension so issuance can be split by principal kind — never
        # the key or secret.
        instrument(:issue) do |event|
          event[:owner_type] = owner.class.name.demodulize
          self.access_key_id ||= Partitia::Iam::AccessKeyId.generate(account_handle: Partitia::Iam.current_account_handle)
          next if secret_digest.present?

          @secret = Partitia::Iam::Secret.generate
          self.secret_digest = Partitia::Iam::Secret.digest(@secret)
          # A credential was minted — owner type + id only, never the key or secret.
          logger.info { "credential issued for #{owner.class.name}##{owner_id}" }
        end
      end

      def owner_is_not_root
        errors.add(:owner, I18n.t("partitia_iam.credential.errors.root_owner")) if owner.is_a?(Partitia::Iam::HumanPrincipal) && owner.root?
      end
    end
  end
end
