# frozen_string_literal: true

require "partitia/support"

module Partitia
  module Cognito
    # Provider connection config — the Authentik/OIDC seam. A Partitia::Support::Config
    # subclass (anyway_config), so every value resolves from
    # config/partitia_cognito.yml → credentials.partitia_cognito → ENV["PARTITIA_COGNITO_*"]
    # with one precedence, the family convention.
    #
    # These are DATA the deploy environment sets. They are distinct from the
    # behavioral inversion SLOTS on the Partitia::Cognito module (identity_resolver,
    # policy_resolver, provider, session_key, after_sign_*_path) — those are
    # callables the host wires and stay as module accessors.
    #
    # client_secret is a SECRET: it resolves from credentials.partitia_cognito.client_secret
    # (or PARTITIA_COGNITO_CLIENT_SECRET) and must never appear as a source literal.
    # issuer/client_id are non-secret connection values (a URL and a public OIDC
    # client identifier). scopes defaults to the OIDC baseline.
    #
    # client_type is how the IdP registered the client: "public" (the default; PKCE
    # alone, no secret is sent even if one is configured) or "confidential" (PKCE
    # plus client_secret, which is then required).
    class Config < Partitia::Support::Config
      CLIENT_TYPES = %w[public confidential].freeze

      config_name :partitia_cognito

      attr_config :issuer, :client_id, :client_secret,
                  client_type: "public",
                  scopes: %w[openid email profile]

      def confidential?
        case client_type.to_s
        when "public" then false
        when "confidential" then true
        else raise ConfigurationError, "partitia_cognito client_type must be one of " \
                                       "#{CLIENT_TYPES.join(', ')} (got #{client_type.inspect})"
        end
      end

      # The secret the token request sends: nil for a public client, the configured
      # one (required) for a confidential client.
      def token_secret
        return nil unless confidential?
        return client_secret unless client_secret.to_s.empty?

        raise ConfigurationError, "partitia_cognito client_type is confidential but no client_secret " \
                                  "is set (credentials.partitia_cognito.client_secret or " \
                                  "PARTITIA_COGNITO_CLIENT_SECRET)"
      end
    end
  end
end
