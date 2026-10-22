require "partitia/iam/version"
require "partitia/iam/engine"

module Partitia
  module Iam
    # Engine-level configuration surface (ADR 0002 §4). Kept deliberately small:
    # the URN partition/region and the server-side HMAC key for secret digests.
    #
    # A Partitia::Support::Config subclass (anyway_config) so every value resolves from
    # config/partitia_iam.yml → credentials.partitia_iam → ENV["PARTITIA_IAM_*"] with one precedence — the
    # family convention. Secrets flow through credentials/ENV, never a literal.
    #
    # partition  — first URN segment, host-configurable (default "cnfs").
    # region     — empty for IAM, mirroring AWS's global IAM service.
    # hmac_key   — server-side key for HMAC-SHA256 secret digests. In production
    #              this MUST come from Rails credentials / ENV. A fixed fallback is
    #              provided so dev/test work out of the box; it is NOT a secret.
    # account_handle — the single-tenant account handle seam (see
    #              Partitia::Iam.current_account_handle below).
    # session_key — session key holding the canonical principal id
    #              (Partitia::Iam::Authenticatable).
    class Config < Partitia::Support::Config
      config_name :partitia_iam

      # Fixed dev/test fallback key. Deterministic so digests round-trip across a
      # process without any host configuration. NOT A SECRET, dev/test only —
      # production hosts override via PARTITIA_IAM_HMAC_KEY / credentials.partitia_iam.hmac_key.
      DEFAULT_HMAC_KEY = "iam-development-hmac-key-not-a-secret"

      attr_config :account_handle,
                  partition: "cnfs",
                  region: "",
                  hmac_key: DEFAULT_HMAC_KEY,
                  session_key: :partitia_iam_user_id
    end

    class << self
      # The memoized config singleton. Kept as the public read/write API the gem
      # and its specs already use (`Partitia::Iam.config.hmac_key`, `Partitia::Iam.config.account_handle = ...`).
      def config
        Config.instance
      end

      def configure
        yield config
      end

      # ROUTING SEAM (ADR 0002 / ADR 0003 boundary).
      #
      # The account handle stamped into AccessKey IDs and URNs. In single-tenant
      # mode (this plan) there is no gem `Tenant` object present, so we mint a
      # real handle once and memoise it on the config (ADR 0002 §2: single-tenant
      # fills the account segment with a REAL handle, never a sentinel). A host can
      # pin it via `Partitia::Iam.configure { |c| c.account_handle = ... }`.
      #
      # Under multi-tenancy the active tenant's handle IS the account handle: the
      # current-tenant string is the Tenant's routing handle after partitia-tenanted
      # keys databases by handle (Plan 001). Do NOT inline the handle anywhere
      # else; this is the one sanctioned source.
      #
      # Precedence: an explicit host pin wins; else the active tenant handle (when
      # tenanted and inside a tenant context); else the single-tenant mint+memoise
      # (ADR 0002 §2 — a real handle, never a sentinel). Single-tenant behavior is
      # unchanged from Plan 001.
      def current_account_handle
        return config.account_handle if config.account_handle

        tenanted_account_handle || (config.account_handle ||= Partitia::Iam::Handle.generate)
      end

      private

      # The active tenant handle when running under partitia-tenanted inside a tenant
      # context, else nil. Guarded so single-tenant apps (no partitia-tenanted, no
      # activerecord-tenanted) never reach this branch. The current-tenant accessor
      # was verified against activerecord-tenanted 0.7.0
      # (ActiveRecord::Tenanted.connection_class.current_tenant).
      def tenanted_account_handle
        return nil unless defined?(Partitia::Tenanted) && defined?(ActiveRecord::Tenanted)

        klass = ActiveRecord::Tenanted.connection_class
        return nil unless klass.respond_to?(:current_tenant)

        klass.current_tenant.presence
      end
    end
  end
end
