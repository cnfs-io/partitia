require "openssl"

module Partitia
  module Iam
    # Long-lived credential secret handling (ADR 0002 §3). The plaintext secret is
    # shown ONCE at creation and never stored; only its HMAC-SHA256 digest is
    # persisted. HMAC (not bcrypt) because API secrets are high-entropy machine
    # credentials — bcrypt's work factor is wasted on urandom and would tax every
    # API request. Verification is constant-time.
    #
    #   plaintext (shown once): iam_secret_<high-entropy>
    #   stored:                 HMAC-SHA256(hex) of the plaintext, keyed by the
    #                           server-side Partitia::Iam.config.hmac_key
    module Secret
      PREFIX = "iam_secret".freeze
      ENTROPY_BYTES = 32

      module_function

      def generate
        "#{PREFIX}_#{SecureRandom.urlsafe_base64(ENTROPY_BYTES)}"
      end

      def digest(plaintext)
        OpenSSL::HMAC.hexdigest("SHA256", hmac_key, plaintext.to_s)
      end

      def verify(plaintext, stored_digest)
        return false if plaintext.to_s.empty? || stored_digest.to_s.empty?

        ActiveSupport::SecurityUtils.secure_compare(digest(plaintext), stored_digest.to_s)
      end

      def hmac_key
        Partitia::Iam.config.hmac_key
      end
    end
  end
end
