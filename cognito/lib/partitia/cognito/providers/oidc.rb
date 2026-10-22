require "jwt"
require "net/http"
require "openssl"
require "json"
require "uri"

module Partitia
  module Cognito
    module Providers
      # Generic OpenID Connect provider. Base subclasses configure it with the
      # issuer URL, client id/secret, and scopes. Verification is delegated to the
      # `jwt` gem (never hand-rolled): RS256 signature against the IdP's JWKS, plus
      # iss/aud/exp and the nonce. Discovery and JWKS are fetched and cached; an
      # unknown `kid` triggers one JWKS refetch (key rotation).
      class Oidc < Base
        # Pin the signature algorithm — never trust the token header's `alg`
        # (defeats alg:none / algorithm-confusion attacks).
        ALGORITHMS = %w[RS256].freeze
        DEFAULT_SCOPES = %w[openid email profile].freeze
        # Connection-level failures talking to the IdP: refused/reset/unreachable
        # (SystemCallError covers the Errno family), open/read timeouts, DNS
        # (SocketError), TLS, and a connection dropped mid-response.
        CONNECTION_ERRORS = [
          SystemCallError, Timeout::Error, SocketError, OpenSSL::SSL::SSLError, EOFError
        ].freeze

        attr_reader :issuer, :client_id

        def initialize(issuer:, client_id:, client_secret: nil, scopes: DEFAULT_SCOPES)
          @issuer = issuer.to_s.chomp("/")
          @client_id = client_id
          @client_secret = client_secret
          @scopes = scopes
        end

        # --- Authorization-code flow with PKCE (S256) ---
        def authorization_url(redirect_uri:, state:, nonce:, code_challenge:)
          uri = URI(discovery.fetch("authorization_endpoint"))
          uri.query = URI.encode_www_form(
            response_type: "code",
            client_id: @client_id,
            redirect_uri: redirect_uri,
            scope: @scopes.join(" "),
            state: state,
            nonce: nonce,
            code_challenge: code_challenge,
            code_challenge_method: "S256"
          )
          uri.to_s
        end

        def exchange_code(code:, redirect_uri:, code_verifier:)
          # External POST to the IdP token endpoint (nested :http span). Never put
          # the form body in the payload — it carries the code + client_secret.
          instrument(:exchange_code) do |event|
            logger.debug { "token exchange: begin" }
            tokens = post_form(discovery.fetch("token_endpoint"), {
              grant_type: "authorization_code",
              code: code,
              redirect_uri: redirect_uri,
              client_id: @client_id,
              client_secret: @client_secret,
              code_verifier: code_verifier
            }.compact)
            logger.debug { "token exchange: ok" }
            # Bounded outcome so exchange failures are countable; never the code,
            # secret, or response body.
            event[:outcome] = "ok"
            tokens
          rescue UnavailableError
            event[:outcome] = "idp_unavailable"
            raise
          rescue StandardError
            event[:outcome] = "failed"
            raise
          end
        end

        # --- ID-token verification -> Assertion ---
        def verify(id_token:, nonce:)
          instrument(:verify) do |event|
            # Rescue INSIDE the block so the outcome dimension lands on the span
            # before the exception marks it errored — failures stay countable by
            # reason (a closed vocabulary), and the re-raise keeps the error status.
            header = JWT.decode(id_token, nil, false).last
            key = signing_key(header["kid"])

            payload, = JWT.decode(
              id_token, key, true,
              algorithms: ALGORITHMS,
              iss: @issuer, verify_iss: true,
              aud: @client_id, verify_aud: true,
              verify_expiration: true
            )

            verify_nonce!(payload, nonce)
            assertion = build_assertion(payload)
            # issuer is a bounded host — a good dimension. The IdP `subject` (sub)
            # is per-user PII and a cardinality bomb: it is NEVER a span attribute
            # (see the telemetry skill's worked example). Outcome is the dimension.
            event[:issuer]  = assertion.issuer
            event[:outcome] = "verified"
            assertion
          rescue JWT::DecodeError => e
            # One-line reason only — never the token or claim contents.
            event[:outcome] = verify_failure_reason(e)
            logger.warn { "verify failed: #{e.message}" }
            raise VerificationError, e.message
          rescue UnavailableError
            # JWKS fetch couldn't reach the IdP — not a token fault.
            event[:outcome] = "idp_unavailable"
            raise
          rescue VerificationError => e
            # nonce mismatch / unknown signing key after refetch — a security outcome.
            event[:outcome] = verify_failure_reason(e)
            logger.warn { "verify failed: #{e.message}" }
            raise
          end
        end

        private

        def verify_nonce!(payload, nonce)
          return if nonce.nil?
          return if payload["nonce"] == nonce

          raise VerificationError, "nonce mismatch"
        end

        # Map a verification exception to a bounded outcome vocabulary — a CLOSED
        # set of reason labels, never the raw message (unbounded / may leak claim
        # contents). This is the span dimension error-rate panels split on.
        def verify_failure_reason(error)
          case error
          when JWT::ExpiredSignature then "expired"
          when JWT::VerificationError then "bad_signature"
          when JWT::DecodeError then "malformed"
          else # our VerificationError (nonce / unknown kid) — classify by cause
            case error.message
            when /nonce/ then "nonce_mismatch"
            when /unknown signing key/ then "unknown_kid"
            else "invalid"
            end
          end
        end

        def build_assertion(payload)
          Partitia::Cognito::Assertion.new(
            issuer: payload["iss"],
            subject: payload["sub"],
            email: payload["email"],
            email_verified: payload["email_verified"],
            name: payload["name"],
            amr: payload["amr"],
            claims: payload
          )
        end

        # Resolve the JWKS key for `kid`, refetching the JWKS once if the kid is
        # unknown (handles rotation).
        def signing_key(kid)
          instrument(:signing_key, kid: kid.to_s) do |event|
            jwk = jwk_for(kid)
            unless jwk
              # Unknown kid: refetch the JWKS once (key rotation). Routine rotation
              # OR an attack probe — the line lets you tell them apart later.
              event[:rotated] = true
              logger.warn { "jwks: unknown kid, refetching (rotation or probe)" }
              @jwks_keys = nil
              jwk = jwk_for(kid)
            end
            raise VerificationError, "unknown signing key: #{kid.inspect}" unless jwk

            JWT::JWK.import(jwk).public_key
          end
        end

        def jwk_for(kid)
          jwks_keys.find { |k| k["kid"] == kid }
        end

        def jwks_keys
          @jwks_keys ||= begin
            logger.debug { "jwks: fetching" }
            fetch_json(discovery.fetch("jwks_uri"), endpoint: "jwks").fetch("keys")
          end
        end

        def discovery
          if @discovery
            logger.debug { "discovery: cache hit" }
            @discovery
          else
            logger.debug { "discovery: fetching" }
            @discovery = fetch_json("#{@issuer}/.well-known/openid-configuration", endpoint: "discovery")
          end
        end

        # `endpoint` is a bounded label ("discovery" / "jwks" / "token") — the span
        # dimension. The full `url` would be a cardinality risk (and belongs only on
        # the debug log line), so it is NOT a span attribute.
        def fetch_json(url, endpoint:)
          instrument(:http, method: "GET", endpoint: endpoint) do |event|
            response = reach_idp(event) { Net::HTTP.get_response(URI(url)) }
            event[:status] = response.code.to_i
            unless response.is_a?(Net::HTTPSuccess)
              # A real fault (IdP down / misconfig) — unavailable, not a token
              # fault. Discovery/JWKS URLs aren't secret.
              event[:outcome] = "idp_unavailable"
              logger.error { "http GET #{url} -> #{response.code}" }
              raise UnavailableError, "identity provider #{issuer_host} answered #{response.code} (#{endpoint})"
            end

            JSON.parse(response.body)
          end
        end

        def post_form(url, form)
          # `form` (code/client_secret) is intentionally NOT in the payload, and
          # the token `url` stays off the span — only the bounded endpoint label.
          instrument(:http, method: "POST", endpoint: "token") do |event|
            response = reach_idp(event) { Net::HTTP.post_form(URI(url), form) }
            event[:status] = response.code.to_i
            unless response.is_a?(Net::HTTPSuccess)
              # Token endpoint: host + status only, never the form body (code/secret).
              logger.error { "http POST #{URI(url).host} -> #{response.code}" }
              raise VerificationError, "POST #{url} -> #{response.code}"
            end

            JSON.parse(response.body)
          end
        end

        # Translate a connection-level failure into UnavailableError, whose
        # message carries the issuer host and the exception class only (never a
        # URL with params, the form body or a secret); the broker logs it at warn.
        # Other errors pass through untouched.
        def reach_idp(event)
          yield
        rescue *CONNECTION_ERRORS => e
          event[:outcome] = "idp_unavailable"
          raise UnavailableError, "identity provider #{issuer_host} unreachable (#{e.class})"
        end

        def issuer_host
          URI(@issuer).host || @issuer
        rescue URI::InvalidURIError
          @issuer
        end
      end
    end
  end
end
