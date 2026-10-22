# Canonical host wiring for the identity architecture (Plan 004). This file is
# the reference for how a host composes partitia-tenanted + iam + partitia-cognito; it
# documents the whole seam in one place.

# --- Tenant selection at the Rack layer -------------------------------------
# partitia-tenanted defaults to resolving the tenant in its controller concern
# (Plan 001), but the broker's OIDC callback runs in a MOUNTED engine that does
# not inherit the host ApplicationController — so tenant context must be
# established earlier, at the Rack layer, to cover host routes AND mounted
# engines uniformly (ADR 0001: DB selection precedes everything). We re-point
# activerecord-tenanted's TenantSelector middleware at a subdomain -> handle
# resolver. Unknown/blank subdomains resolve to nil (run untenanted), leaving the
# concern's not-found seam to handle host routes.
# Set in after_initialize so it wins over partitia-tenanted's engine-initializer
# default (which neutralizes the middleware for its own concern-based path,
# Plan 001). The middleware reads the resolver lazily on the first request, well
# after this runs.
Rails.application.config.after_initialize do
  Rails.application.config.active_record_tenanted.tenant_resolver = ->(request) do
    # The platform (App Admin) login flow authenticates AS the platform — its
    # OIDC round-trip must run in the reserved database. A dedicated entry point
    # sets a session flag (the reserved handle never resolves from a subdomain,
    # ADR 0003 §2). Otherwise: subdomain -> handle; blank/unknown -> nil.
    next Partitia::Tenanted::RESERVED_HANDLE if request.session[:platform_auth]

    subdomain = Partitia::Tenanted.tenant_resolver.call(request)
    subdomain && Partitia::Tenanted::Tenant.find_by(subdomain: subdomain)&.handle
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
