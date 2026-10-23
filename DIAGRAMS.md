# Diagrams

High-level pictures of the partitia gems, drawn from the code (2026-10-22). `ARCHITECTURE.md` holds the
contract they illustrate.

## 1. The gems and how they relate

The dependencies here are declared in the gemspecs. The integrations between engines are seams:
an engine checks `defined?(...)`, or the host wires it in an initializer. No engine requires a
sibling it doesn't declare, so an app picks any subset its recipe names (`single`: everything
except tenanted and ui; `multi`: adds tenanted).

```mermaid
flowchart TB
  host["Host Rails app<br/>(pt new single | multi)"]

  subgraph partitia["partitia gems"]
    support["partitia-support<br/>Config (anyway_config), plugin registry,<br/>migrations_paths, Instrumentable, UrnConfig"]
    dev["partitia-dev<br/>console tooling (pry), dev only"]
    telemetry["partitia-telemetry<br/>OTel bridge, rack_tracing, sentry-rails wiring"]
    tenanted["partitia-tenanted<br/>tenant from subdomain, DB per tenant,<br/>platform DB, tenant console"]
    iam["partitia-iam<br/>principals, accounts, identity links,<br/>Resolution, root + bootstrap token"]
    cognito["partitia-cognito<br/>OIDC broker: PKCE, ID-token verification"]
    ui["partitia-ui<br/>Phlex + RubyUI (shelved until D9)"]
  end

  subgraph ext["key upstream gems"]
    anyway["anyway_config"]
    art["activerecord-tenanted"]
    jwt["jwt"]
    otel["opentelemetry-*"]
    phlex["phlex-rails"]
  end

  subgraph pcm["pcm services (dev)"]
    authentik[("Authentik<br/>IdP")]
    glitchtip[("GlitchTip<br/>errors")]
    tempo[("otel-collector to Tempo,<br/>Grafana")]
  end

  host --> support & dev & telemetry & tenanted & iam & cognito
  host -.-> ui

  telemetry --> support
  tenanted --> support
  iam --> support
  cognito --> support
  ui --> support

  support --> anyway
  tenanted --> art
  cognito --> jwt
  telemetry --> otel
  ui --> phlex

  cognito -. "identity_resolver<br/>(wired in the host's initializer)" .-> iam
  tenanted -. "before_sign_in hook:<br/>no sign-in without a tenant DB" .-> cognito
  iam -. "TenantSeeder on after_provision:<br/>account + root per tenant" .-> tenanted
  tenanted & iam & cognito -. "partitia_* events<br/>(ActiveSupport::Notifications)" .-> telemetry

  cognito == "OIDC" ==> authentik
  telemetry == "OTLP/HTTP :4318" ==> tempo
  telemetry == "Sentry DSN" ==> glitchtip
```

**Legend:**
- Solid arrows are gemspec dependencies.
- Dotted arrows are optional seams.
- Thick arrows are network calls.

Each engine's gemspec declares the pcm services it needs, in `partitia.services`:
- cognito: `authentik`
- telemetry: `telemetry glitchtip`

`pt services` provisions them.

## 2. Sign-in (OIDC authorization code + PKCE through Authentik)

This is a multi-tenant app on `acme.localhost`. In a single-tenant app, tenanted's two steps aren't there and everything runs in the one database.
- **First sign-in:** carries `?link_token=` from `bin/rails partitia:iam:bootstrap`. That claims the root principal.
- **Later sign-ins:** need no token.

```mermaid
sequenceDiagram
  autonumber
  actor B as Browser
  participant T as tenanted<br/>(Rack middleware)
  participant C as cognito<br/>SessionsController
  participant A as Authentik<br/>(pcm, :9000)
  participant I as iam<br/>Resolution
  participant DB as acme's database

  B->>T: GET acme.localhost/auth/login?link_token=…
  T->>T: subdomain "acme" to Tenant, select acme's DB<br/>(unknown: 302 /tenant-unknown, apex: 404)
  T->>C: request (tenant.* on the server span)
  C->>C: before_sign_in hooks (tenanted's: a DB is selected)
  C->>C: state, nonce, PKCE verifier (+ link_token) into the session
  C-->>B: 302 authorize?client_id=app&redirect_uri=…/auth/callback<br/>&code_challenge=S256(verifier)&state&nonce
  B->>A: GET /application/o/authorize/
  A-->>B: login flow (identification, password)
  B->>A: credentials (akadmin)
  A-->>B: 302 acme.localhost/auth/callback?code&state<br/>(redirect URI matched: strict apex, regex for tenants)
  B->>T: GET /auth/callback?code&state
  T->>C: (acme's DB selected)
  C->>C: state == stashed state (constant-time)
  C->>A: POST /token: code + code_verifier (public client, no secret)
  A-->>C: id_token (+ access_token)
  C->>A: GET discovery + JWKS (cached, refetched on an unknown kid)
  C->>C: verify RS256 signature, iss (exact), aud, exp, nonce to Assertion
  C->>I: identity_resolver(assertion, policy, link_token)
  I->>DB: find identity link (iss, sub)
  alt known identity
    DB-->>I: principal
  else link_token valid (first sign-in)
    I->>DB: link identity to root, consume token
  else unknown (policy invite_only)
    I-->>C: failure unknown_identity
    C-->>B: 302 after_sign_out_path + flash
  end
  I-->>C: success(principal)
  C->>C: reset_session, session[:partitia_iam_user_id] = principal.id
  C-->>B: 302 /me
```

**Failure paths not drawn:**
- Authentik unreachable: login and callback answer 503.
- State mismatch or verification failure: redirect with a flash.

Every step emits a `partitia_cognito.*` event, so the whole flow is one trace under the request's server span.
