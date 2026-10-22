module Partitia
  module Iam
    # The verified authentication event handed across the broker↔IAM seam
    # (ADR 0004). A plain, immutable value object carrying exactly the contract
    # fields — it proves an authentication *event*; it says nothing about whether
    # the person exists in our system. Resolution turns it into a principal.
    class Assertion
      ATTRIBUTES = %i[issuer subject email email_verified name amr claims].freeze

      attr_reader(*ATTRIBUTES)

      def initialize(issuer:, subject:, email: nil, email_verified: nil, name: nil, amr: nil, claims: {})
        @issuer = issuer
        @subject = subject
        @email = email
        @email_verified = email_verified
        @name = name
        @amr = amr
        @claims = claims || {}
      end

      # Accept either an Assertion or a plain hash/keyword set of the contract
      # fields (the broker passes a value object or hash — ADR 0004).
      def self.wrap(assertion)
        return assertion if assertion.is_a?(Assertion)

        attrs = assertion.to_h.symbolize_keys.slice(*ATTRIBUTES)
        new(**attrs)
      end

      # A non-blank name for a JIT-created principal (Principal requires one):
      # the display name, else the email, else the opaque subject.
      def display_name
        name.presence || email.presence || subject
      end
    end
  end
end
