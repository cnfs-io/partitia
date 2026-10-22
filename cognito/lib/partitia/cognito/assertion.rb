module Partitia
  module Cognito
    # The verified authentication event the broker hands across the seam to IAM
    # (ADR 0004). An immutable value object carrying EXACTLY the contract fields —
    # extending it is additive; renaming/repurposing a field is a breaking change.
    # It proves an authentication event; it says nothing about whether the person
    # exists in our system (that is resolution's job).
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
        @claims = (claims || {}).freeze
        freeze
      end

      def to_h
        ATTRIBUTES.to_h { |attr| [ attr, public_send(attr) ] }
      end
    end
  end
end
