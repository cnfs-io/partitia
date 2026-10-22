require "zlib"

module Iam
  # Self-describing, plaintext, versioned, checksummed AccessKey ID (ADR 0002 §3):
  #
  #   iam_<v>_<accounthandle>_<random><checksum>
  #   e.g. iam_v1_a7f3k2xy_qm4t9v...<6-char checksum>
  #
  # Plaintext and split-to-parse — NO hashids, NO reversible obfuscation. The
  # account handle is recovered by string split (the dependency-free
  # decode-before-query routing path). The fixed `iam_` prefix enables
  # leaked-credential scanning. The version segment makes scheme rotation
  # visible and routable without decoding.
  #
  # CHECKSUM: base32(CRC32(body)) over the key body preceding the checksum,
  # left-padded to CHECKSUM_LEN. CRC32 is a cheap typo/tamper screen so malformed
  # keys are rejected before any DB or HMAC work — it is integrity-of-shape, not
  # a MAC (the HMAC secret digest is the real authenticator). ADR 0002 "open
  # items" defers the final random-length/checksum tuning to a security pass;
  # round-trip stability + tamper rejection is what is required now.
  module AccessKeyId
    PREFIX = "iam".freeze
    VERSION = "v1".freeze
    RANDOM_LEN = 20
    CHECKSUM_LEN = 6
    ALPHABET = Iam::Handle::ALPHABET

    FORMAT = /\A#{PREFIX}_(v\d+)_([#{ALPHABET}]+)_([#{ALPHABET}]+)\z/

    # Parsed result. `valid?` is true only when the shape matched AND the
    # recomputed checksum agrees with the embedded one.
    Parsed = Data.define(:version, :account_handle, :random, :checksum, :checksum_ok) do
      def valid? = checksum_ok
    end

    module_function

    def generate(account_handle:)
      random = Array.new(RANDOM_LEN) { ALPHABET[SecureRandom.random_number(ALPHABET.size)] }.join
      body = "#{PREFIX}_#{VERSION}_#{account_handle}_#{random}"
      "#{body}#{checksum_for(body)}"
    end

    # Never raises — malformed input returns an invalid Parsed so callers can
    # reject before touching the DB.
    def parse(str)
      m = FORMAT.match(str.to_s)
      return Parsed.new(version: nil, account_handle: nil, random: nil, checksum: nil, checksum_ok: false) unless m

      version, account_handle, tail = m.captures
      return invalid(version, account_handle) if tail.length <= CHECKSUM_LEN

      random = tail[0...-CHECKSUM_LEN]
      checksum = tail[-CHECKSUM_LEN..]
      body = "#{PREFIX}_#{version}_#{account_handle}_#{random}"
      Parsed.new(
        version: version,
        account_handle: account_handle,
        random: random,
        checksum: checksum,
        checksum_ok: secure_equal(checksum, checksum_for(body))
      )
    end

    def valid?(str)
      parse(str).valid?
    end

    def invalid(version, account_handle)
      Parsed.new(version: version, account_handle: account_handle, random: nil, checksum: nil, checksum_ok: false)
    end

    def checksum_for(body)
      base32(Zlib.crc32(body)).rjust(CHECKSUM_LEN, ALPHABET[0])[-CHECKSUM_LEN..]
    end

    # Positional encoding of a non-negative integer over the handle alphabet.
    def base32(int)
      return ALPHABET[0] if int.zero?

      out = +""
      while int.positive?
        out.prepend(ALPHABET[int % ALPHABET.size])
        int /= ALPHABET.size
      end
      out
    end

    def secure_equal(a, b)
      ActiveSupport::SecurityUtils.secure_compare(a, b)
    end
  end
end
