# partitia-cognito configuration (authentication broker).
#
# Two distinct kinds of setting live here:
#   * PROVIDER CONNECTION CONFIG — data (issuer, client_id, client_secret,
#     scopes), read from Partitia::Cognito::Config. That subclass resolves each value
#     from config/partitia_cognito.yml → credentials.partitia_cognito → ENV["PARTITIA_COGNITO_*"].
#     Never inline a secret and never bare-fetch it from ENV here.
#   * INVERSION SLOTS — callables the host wires (identity_resolver,
#     policy_resolver, redirect paths). Two of them (provider, identity_resolver)
#     have NO default and raise ConfigurationError if left unset.

# --- Provider (REQUIRED) --------------------------------------------------
#
# Register the Authentik (OIDC) provider and make it active. Its connection
# values come from Partitia::Cognito::Config — set them where they belong:
#
#   * issuer / client_id — non-secret. In config/partitia_cognito.yml (the
#     installer wrote one pointing development at pcm's Authentik: `pcm up
#     authentik`), or override with PARTITIA_COGNITO_ISSUER / PARTITIA_COGNITO_CLIENT_ID.
#     Authentik's OIDC issuer is per-application:
#         http://localhost:9000/application/o/<app-slug>/
#   * client_secret — SECRET. Put it in Rails credentials (never inline it):
#         bin/rails credentials:edit
#         partitia_cognito:
#           client_secret: <value>
#     or supply PARTITIA_COGNITO_CLIENT_SECRET in the environment.
#
# The redirect URI you register in Authentik is your engine mount + "/callback"
# (e.g. http://localhost:3000/auth/callback).
Partitia::Cognito::Providers::Registry.register(
  :authentik,
  Partitia::Cognito::Providers::Authentik.new(
    issuer:        Partitia::Cognito::Config.issuer,
    client_id:     Partitia::Cognito::Config.client_id,
    client_secret: Partitia::Cognito::Config.client_secret,
    scopes:        Partitia::Cognito::Config.scopes
  )
)

Partitia::Cognito.provider = Partitia::Cognito::Providers::Registry.fetch(:authentik)

# --- Identity resolver: the broker -> IAM seam (REQUIRED) -----------------
#
# A callable (assertion, policy, link_token) -> result, where result responds
# to #success?, #principal (which responds to #id), and #failure_reason
# (ADR 0004). This is the ONE place the broker touches iam; the reference is
# resolved lazily so the two gems stay independent (neither requires the other).
Partitia::Cognito.identity_resolver = ->(assertion, policy, link_token) {
  Partitia::Iam::Resolution.resolve(assertion:, policy:, link_token:)
}

# --- Policy resolver ------------------------------------------------------
#
# Maps a request to the policy IAM applies. The gem default fails CLOSED to
# :invite_only — a login with no pre-existing invite link is rejected. A test
# app usually wants JIT provisioning, where an unknown-but-verified Authentik
# user gets a principal created on the spot:
Partitia::Cognito.policy_resolver = ->(_request) { :jit }
#
# Fail-closed default (uncomment to require invites):
# Partitia::Cognito.policy_resolver = ->(_request) { :invite_only }
#
# Per-route policy (e.g. JIT only on a dedicated signup path):
# Partitia::Cognito.policy_resolver = ->(request) {
#   request.path.start_with?("/auth/login") ? :jit : :invite_only
# }

# --- Redirect targets (optional) ------------------------------------------
#
# Where to land after sign-in / sign-out. A string or a callable evaluated in
# controller context. Both default to "/".
# Partitia::Cognito.after_sign_in_path  = "/"
# Partitia::Cognito.after_sign_out_path = "/"

# --- Session key (optional) -----------------------------------------------
#
# Holds the canonical principal id after a successful resolution. Must match
# Partitia::Iam.config.session_key (both default to :partitia_iam_user_id — leave alone unless you
# change both).
# Partitia::Cognito.session_key = :partitia_iam_user_id
