# Canonical host wiring for the identity architecture (Plan 004). This file is
# the reference for how a host composes partitia-tenanted + iam + partitia-cognito; it
# documents the whole seam in one place.

# --- Tenant selection at the Rack layer -------------------------------------
# partitia-tenanted selects the tenant's database at the Rack layer itself
# (Partitia::Tenanted.request_handle, wired by its engine), so mounted engines
# such as the broker's /auth callback run in the tenant's database with no app
# wiring. The dummy adds one thing: the platform (App Admin) login flow
# authenticates AS the platform, so its OIDC round-trip must run in the reserved
# database. A dedicated entry point sets a session flag (the reserved handle
# never resolves from a subdomain, ADR 0003 §2). Set in after_initialize so it
# wins over the engine's default; the middleware reads the resolver lazily on
# the first request.
Rails.application.config.after_initialize do
  Rails.application.config.active_record_tenanted.tenant_resolver = ->(request) do
    next Partitia::Tenanted::RESERVED_HANDLE if request.session[:platform_auth]

    Partitia::Tenanted.request_handle(request)
  end
end

# --- Broker -> IAM resolution seam (ADR 0004) -------------------------------
Partitia::Cognito.identity_resolver = ->(assertion, policy, link_token) do
  Partitia::Iam::Resolution.resolve(assertion: assertion, policy: policy, link_token: link_token)
end

# --- Which policy applies (ADR 0004) ----------------------------------------
# End-users self-serve (JIT) from the public /app namespace; everyone else is
# invite-only. The broker resolves policy at CALLBACK time (when only the
# callback request is visible), so the originating namespace's intent is carried
# through the OIDC round-trip in the session — set by the /app login entry point.
Partitia::Cognito.policy_resolver = ->(request) do
  (request.session[:oidc_policy].presence || "invite_only").to_sym
end

# --- After sign-in / sign-out ------------------------------------------------
# Land on "/" (home renders in any context, tenanted or not). Specs then GET the
# protected route (/dashboard for tenants, /tenants for the platform console)
# explicitly to prove the established session grants access.
Partitia::Cognito.after_sign_in_path  = "/"
Partitia::Cognito.after_sign_out_path = "/"

# --- Platform console guard (ADR 0003 §7) -----------------------------------
# Allow iff the session resolves to a principal in the RESERVED database (an App
# Admin); deny otherwise. Runs in controller context (instance_exec). Kept as a
# named constant so the test harness can re-apply it after per-example resets.
IDENTITY_CONSOLE_GUARD = lambda do
  principal_id = session[Partitia::Cognito.session_key]
  allowed = principal_id.present? &&
            Partitia::Tenanted.with_platform { Partitia::Iam::Principal.exists?(id: principal_id) }
  head :forbidden unless allowed
end
Partitia::Tenanted.platform_console_guard = IDENTITY_CONSOLE_GUARD

# --- Provider (Authentik) ----------------------------------------------------
# Registered from env-style config; specs override the HTTP surface with the
# WebMock OIDC harness (the defaults match the harness's issuer/client id).
Partitia::Cognito::Providers::Registry.register(
  :authentik,
  Partitia::Cognito::Providers::Authentik.new(
    issuer: ENV.fetch("AUTHENTIK_ISSUER", "https://idp.example"),
    client_id: ENV.fetch("AUTHENTIK_CLIENT_ID", "test-client"),
    client_secret: ENV.fetch("AUTHENTIK_CLIENT_SECRET", "secret")
  )
)
Partitia::Cognito.provider = Partitia::Cognito::Providers::Registry.fetch(:authentik)
