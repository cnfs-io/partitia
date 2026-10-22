require "cnfs_support/logging"
require "cnfs_support/instrumentable"

module CnfsCognito
  module Providers
    # Raised on any verification miss (bad signature, wrong iss/aud, expired,
    # nonce mismatch, unknown kid, malformed token, HTTP failure). The broker
    # never leaks its message into a user-facing error.
    class VerificationError < CnfsCognito::Error; end

    # The provider duck (Plan 003 WS2). Nothing outside a provider knows which
    # IdP is configured; the broker talks only to this surface.
    class Base
      # Providers are POROs, so mix in `logger` and `instrument` explicitly
      # (subclasses inherit both). The class lives 3 levels deep, but
      # component_tag keys off the first segment — CnfsCognito — so both the log
      # tag and the composed event name are a flat "cnfs_cognito"; the concrete
      # provider (e.g. "oidc") is the subject. Events are cnfs_cognito.oidc.<verb>.
      include CnfsSupport::Logging
      include CnfsSupport::Instrumentable

      # Build the IdP authorization URL for the auth-code + PKCE flow.
      def authorization_url(redirect_uri:, state:, nonce:, code_challenge:)
        raise NotImplementedError, "#{self.class}#authorization_url"
      end

      # Exchange an authorization code for the raw token response (a Hash).
      def exchange_code(code:, redirect_uri:, code_verifier:)
        raise NotImplementedError, "#{self.class}#exchange_code"
      end

      # Verify an ID token and return a CnfsCognito::Assertion, or raise
      # VerificationError on any miss.
      def verify(id_token:, nonce:)
        raise NotImplementedError, "#{self.class}#verify"
      end
    end
  end
end
