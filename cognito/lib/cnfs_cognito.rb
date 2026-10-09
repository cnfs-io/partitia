require "cnfs_cognito/version"
require "cnfs_cognito/engine"
require "cnfs_cognito/config"

# CnfsCognito is the authentication BROKER (AWS Cognito analog, ADR 0001). It
# runs OIDC/OAuth flows against a registry of pluggable providers (Authentik
# first), verifies the IdP response into an Assertion, and hands that to a
# configured identity resolver — it never references Iam:: constants and stores
# no identities of its own.
#
# The configuration surface is the house inversion-slot style: plain accessors
# with safe defaults, except the two seams that MUST be wired by the host
# (identity_resolver, provider), which fail loudly if used unset.
module CnfsCognito
  class Error < StandardError; end
  class ConfigurationError < Error; end

  class << self
    attr_writer :identity_resolver, :policy_resolver, :session_key,
                :provider, :after_sign_in_path, :after_sign_out_path

    # The broker↔IAM seam (ADR 0004): a callable
    # (assertion, policy, link_token) -> result, where result responds to
    # #success?, #principal (which responds to #id) and #failure_reason. NO
    # default — the host wires it to Iam::Resolution.
    def identity_resolver
      @identity_resolver || raise(ConfigurationError, <<~MSG)
        CnfsCognito.identity_resolver is not configured.
        Set it to a callable (assertion, policy, link_token) -> result, e.g.:
          CnfsCognito.identity_resolver = ->(assertion, policy, link_token) {
            Iam::Resolution.resolve(assertion:, policy:, link_token:)
          }
      MSG
    end

    # Maps a request to the policy IAM should apply (:jit | :invite_only). The
    # host decides which route/population gets which policy. Default fails closed
    # to :invite_only (ADR 0004).
    def policy_resolver
      @policy_resolver ||= ->(_request) { :invite_only }
    end

    # Session key holding the canonical principal id after a successful
    # resolution (matches Iam's default).
    def session_key
      @session_key ||= :iam_user_id
    end

    # The active provider instance (see Providers::Registry). NO default — the
    # host registers and assigns one.
    def provider
      @provider || raise(ConfigurationError, <<~MSG)
        CnfsCognito.provider is not configured.
        Register a provider and assign it, e.g.:
          CnfsCognito.provider = CnfsCognito::Providers::Registry.fetch(:authentik)
      MSG
    end

    # Where to land after sign-in / sign-out. A string or a callable evaluated in
    # controller context.
    def after_sign_in_path
      @after_sign_in_path ||= "/"
    end

    def after_sign_out_path
      @after_sign_out_path ||= "/"
    end

    # Reset all slots — for tests and re-configuration.
    def reset_configuration!
      @identity_resolver = @policy_resolver = @session_key = @provider =
        @after_sign_in_path = @after_sign_out_path = nil
    end
  end
end

require "cnfs_cognito/assertion"
require "cnfs_cognito/providers"
