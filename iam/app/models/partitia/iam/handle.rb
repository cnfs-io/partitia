module Partitia
  module Iam
    # Opaque, system-generated account handle (ADR 0002 §1). Crockford base32 with
    # the visually ambiguous characters removed. The Account record's mutable
    # `name` carries all human/branding churn; this handle is a routing fact and is
    # immutable by contract (enforced on the owning model, not here).
    #
    # Alphabet: Crockford base32 lowercased, minus 0/1/i/l/o/u — i.e. no ambiguous
    # 0/O/1/I (ADR 0001 #3). 30 symbols. Length 8 (~39 bits) is ample to keep
    # single-tenant handles collision-free when installs later federate.
    module Handle
      ALPHABET = "23456789abcdefghjkmnpqrstvwxyz".freeze
      LENGTH = 8
      FORMAT = /\A[#{ALPHABET}]{#{LENGTH}}\z/

      module_function

      def generate(length: LENGTH)
        Array.new(length) { ALPHABET[SecureRandom.random_number(ALPHABET.size)] }.join
      end

      def valid?(str)
        FORMAT.match?(str.to_s)
      end
    end
  end
end
