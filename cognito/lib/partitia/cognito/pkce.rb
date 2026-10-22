require "securerandom"
require "digest"
require "base64"

module CnfsCognito
  # PKCE (RFC 7636), S256 method. The broker generates a high-entropy verifier
  # per login, stashes it in the session, and sends only its SHA-256 challenge
  # to the IdP.
  module Pkce
    module_function

    def verifier
      SecureRandom.urlsafe_base64(64)
    end

    def challenge(verifier)
      Base64.urlsafe_encode64(Digest::SHA256.digest(verifier.to_s), padding: false)
    end
  end
end
