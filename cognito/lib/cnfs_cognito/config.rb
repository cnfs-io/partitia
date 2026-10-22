# frozen_string_literal: true

require "cnfs_support"

module CnfsCognito
  # Provider connection config — the Authentik/OIDC seam. A CnfsSupport::Config
  # subclass (anyway_config), so every value resolves from
  # config/cnfs_cognito.yml → credentials.cnfs_cognito → ENV["CNFS_COGNITO_*"]
  # with one precedence, the family convention.
  #
  # These are DATA the deploy environment sets. They are distinct from the
  # behavioral inversion SLOTS on the CnfsCognito module (identity_resolver,
  # policy_resolver, provider, session_key, after_sign_*_path) — those are
  # callables the host wires and stay as module accessors.
  #
  # client_secret is a SECRET: it resolves from credentials.cnfs_cognito.client_secret
  # (or CNFS_COGNITO_CLIENT_SECRET) and must never appear as a source literal.
  # issuer/client_id are non-secret connection values (a URL and a public OIDC
  # client identifier). scopes defaults to the OIDC baseline.
  class Config < CnfsSupport::Config
    config_name :cnfs_cognito

    attr_config :issuer, :client_id, :client_secret,
                scopes: %w[openid email profile]
  end
end
