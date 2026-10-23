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
  host["Host Rails app<br/>(cnfs new single | multi)"]

  subgraph partitia["partitia gems"]
    support["partitia-support<br/>Config (anyway_config), plugin registry,<br/>migrations_paths, Instrumentable, UrnConfig"]
    dev["partitia-dev<br/>console tooling (pry), dev only"]
    telemetry["partitia-telemetry<br/>OTel bridge, rack_tracing, sentry-rails wiring"]
    tenanted["partitia-tenanted<br/>tenant from subdomain, DB per tenant,<br/>platform DB, tenant console"]
    iam["partitia-iam<br/>principals, accounts, identity links,<br/>Resolution, root + bootstrap token"]
    cognito["partitia-cognito<br/>OIDC broker: PKCE, ID-token verification"]
    ui["partitia-ui<br/>Phlex + RubyUI: operator screens,<br/>default shell (ADR 0008, D9)"]
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

`cnfs services` provisions them.

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

## 3. Databases and where each engine's tables go

A single app has the one `primary` database. A multi app (with tenanted) has no `primary`: a
`global` database for the tenant registry, and a `tenant` database config with `tenanted: true`
that activerecord-tenanted turns into one SQLite file per handle. The reserved `platform`
handle is one of those files.

A model's database comes from its base class:
- `Partitia::Tenanted::GlobalRecord` connects to `global`.
- The host's `ApplicationRecord` calls `tenanted "tenant"`.
- tenanted's `to_prepare` makes every registered engine's `ApplicationRecord` (iam's) a
  `subtenant_of` it.

In a single app nothing reassigns iam's models, so they land in `primary`.

```mermaid
flowchart LR
  subgraph single["single app"]
    direction TB
    s_ar["host ApplicationRecord<br/>Partitia::Iam::ApplicationRecord"]
    s_primary[("primary<br/>storage/development.sqlite3<br/>partitia_iam_* + host tables")]
    s_ar --> s_primary
  end

  subgraph multi["multi app (+ tenanted)"]
    direction TB
    m_global_rec["Partitia::Tenanted::GlobalRecord<br/>(Tenant, host global models)"]
    m_ar["host ApplicationRecord: tenanted 'tenant'<br/>Partitia::Iam::ApplicationRecord: subtenant_of"]
    m_global[("global<br/>storage/development.sqlite3<br/>partitia_tenanted_tenants")]
    m_platform[("tenant 'platform' (reserved)<br/>storage/development/platform.sqlite3<br/>partitia_iam_*: the platform's identity")]
    m_acme[("tenant #lt;handle#gt;, e.g. acme<br/>storage/development/9xskt3v6.sqlite3<br/>partitia_iam_* + host tables")]
    m_tmpl[("development-tenant<br/>activerecord-tenanted's default tenant")]
    m_global_rec --> m_global
    m_ar --> m_platform & m_acme & m_tmpl
  end
```

**Not drawn:**
- Production's Solid databases (`cache`, `queue`, `cable`). tenanted's installer keeps them with
  their own `db/*_migrate` folders, and support's installer wires only `primary`.
- The platform database has the full tenant schema, host tables included. Only
  `with_platform`'s scope guard keeps code to the `partitia_iam_` tables there.
- cognito, telemetry and support have no tables.

### How migrations reach each database

Nothing is copied into the app. Each engine adds itself to `Partitia::Support.plugins`. At boot,
support's railtie walks the host (`Rails` first) and then every plugin. For each scope in
`migrations_paths_for` it collects the absolute folder that exists. `database.yml` reads the result
through ERB when Rails loads it.

```mermaid
flowchart LR
  subgraph scopes["migrations_paths_for"]
    sp["support's default<br/>primary: db/migrate"]
    tp["tenanted's Engine class body replaces it<br/>tenant: db/migrate<br/>global: db/global_migrate"]
    sp -. "multi app" .-> tp
  end

  subgraph walk["support railtie initializer"]
    host["Rails (the host) first:<br/>db/migrate, db/global_migrate if present"]
    iam["partitia-iam<br/>db/migrate (4 tables)"]
    ten["partitia-tenanted<br/>db/global_migrate (tenants)"]
    cog["partitia-cognito<br/>(no migrations)"]
  end

  reg["Partitia::Support.migrations_paths<br/>{ primary: [...] } or<br/>{ tenant: [...], global: [...] }"]

  scopes --> walk
  host & iam & ten & cog --> reg

  subgraph yml["config/database.yml (ERB)"]
    y1["single, written by support:install<br/>primary: migrations_paths: #lt;%= ...[:primary] %#gt;"]
    y2["multi, written by tenanted:install (stock file only)<br/>global: ...[:global]<br/>tenant: ...[:tenant], tenanted: true"]
  end

  reg --> y1 & y2
  y1 --> dbp[("primary")]
  y2 --> dbg[("global")]
  y2 --> dbt[("every tenant DB<br/>incl. platform")]
```

Who writes what:
- support's installer injects the `[:primary]` line into each environment's primary database.
  It leaves an environment that already reads the registry for any scope alone.
- tenanted's installer replaces a stock `database.yml` and stops on a customized one. That is
  why it runs first.
- iam's installer only checks that the file reads the registry.

The scopes are swapped at load time: tenanted's `Engine` class body runs at `Bundler.require`,
before support's initializer walks the plugins.

## 4. Provisioning a tenant

A tenant is created from the console, from seeds (`cnfs new multi` seeds `acme`), from `/tenants`, or
by `Partitia::Tenanted::Tenant.create!`. All of these go through the `after_create` callback below.
The platform database goes through the same `run_provision`, with a context that has the same
shape (`#name`, `#owner_email`), so iam seeds both with one code path.

The plaintext link token from provisioning is only kept in memory (`last_bootstrap_token`), and
the database stores only its digest. So the first sign-in takes its token from
`partitia:iam:bootstrap`, which issues a new one.

```mermaid
sequenceDiagram
  autonumber
  actor Op as Operator<br/>(console, seeds, /tenants)
  participant T as Tenant<br/>(global DB)
  participant P as Partitia::Tenanted<br/>run_provision
  participant AR as activerecord-tenanted
  participant DB as the new database
  participant S as iam TenantSeeder

  alt a tenant
    Op->>T: Tenant.create!(name, subdomain, owner_email)
    T->>T: assign_handle (8 chars, never "platform"), validate
    T->>T: INSERT partitia_tenanted_tenants (transaction still open)
    T->>P: after_create: run_provision(handle, tenant, cleanup_on_failure: true)
  else the platform (once per environment)
    Op->>P: provision_platform!(owner_email:)
    P->>AR: tenant_exist?("platform")
    Note over P: exists: return (no Tenant row, ever)
    P->>P: run_provision("platform", PlatformContext, cleanup_on_failure: false)
  end

  Note over P: span partitia_tenanted.provisioning.run
  P->>AR: create_tenant(handle, if_not_exists: true)
  AR->>DB: create storage/#lt;env#gt;/#lt;handle#gt;.sqlite3
  AR->>DB: load db/tenant_schema.rb, then pending migrations_paths[:tenant]
  P->>AR: with_tenant(handle)
  loop each Partitia::Tenanted.after_provision hook
    P->>S: call(context), span partitia_iam.tenant_seeder.seed
    S->>DB: Account.instance(name: context.name)
    S->>DB: HumanPrincipal root (email: owner_email)
    S->>DB: root.issue_link_token! (digest stored, 7 days)
    S-->>S: plaintext kept in last_bootstrap_token
  end
  alt a hook raises
    P->>AR: destroy_tenant(handle) (tenants only, platform is left for recovery)
    P-->>T: re-raise, the Tenant row rolls back
  else
    P-->>Op: provisioned
  end

  Note over Op,S: Later, for the first sign-in
  Op->>T: bin/rails partitia:iam:bootstrap TENANT=acme
  T->>AR: Tenant.find_by(subdomain) then with_tenant(handle)<br/>(TENANT=platform: with_platform)
  AR->>DB: Bootstrap.call: root claimed?
  alt root has an identity link
    DB-->>Op: ROOT=claimed (no token)
  else unclaimed
    DB-->>Op: ROOT=unclaimed, LINK_TOKEN=... (new token, the old one stops working)
  end
```

**Not drawn:**
- In a single app nothing provisions. `partitia:iam:bootstrap` with no `TENANT` seeds the app's
  database through the same `TenantSeeder` on its first run.
- The single `last_bootstrap_token` slot races under concurrent provisioning. The code says so.

## 5. A request through a multi app

This is the middleware stack of a fresh `cnfs new multi` app, from `bin/rails middleware` (Rails 8.1,
development). The stock Rails middlewares are grouped.
- The OTel server span opens at the very top.
- tenanted's database selection is the **last** middleware, after cookies, session and flash.
  activerecord-tenanted adds it with `config.middleware.use`.
- The mounted cognito engine's controller inherits `ActionController::Base`, not the host's
  `ApplicationController`, so it never runs `TenantResolution`. That is why the database has to
  be selected at the Rack layer.

```mermaid
flowchart TB
  req(["GET acme.localhost:3000/..."])
  events["Rack::Events + OTel Rack EventHandler<br/>server span opens (rack_tracing)"]
  rails1["HostAuthorization ... RequestId, RemoteIp, Rails::Rack::Logger<br/>(stock)"]
  exc["ShowExceptions, Sentry CaptureExceptions,<br/>DebugExceptions, Sentry RescuedExceptionInterceptor"]
  rel["Reloader, Callbacks, Migration::CheckPending"]
  sess["Cookies, Session::CookieStore, Flash"]
  rails2["CSP, Head, ConditionalGet, ETag, TempfileReaper"]
  sel["ActiveRecord::Tenanted::TenantSelector<br/>resolver: Partitia::Tenanted.request_handle<br/>subdomain to Tenant.find_by to handle"]
  routes{"routes"}

  req --> events --> rails1 --> exc --> rel --> sess --> rails2 --> sel
  sel -- "known: with_tenant(handle)" --> routes
  sel -- "blank or unknown: untenanted" --> routes

  subgraph hostc["host ApplicationController"]
    tr["around_action TenantResolution#switch<br/>unknown: tenant_not_found_handler, 302 /tenant-unknown<br/>known: with_tenant(handle), a no-op here"]
    authn["MeController: include Partitia::Iam::Authenticatable<br/>before_action resolve_current_user (session id to Principal)"]
    tr --> authn
  end

  subgraph authc["/auth: Partitia::Cognito::SessionsController (ActionController::Base)"]
    bsi["before_action run_before_sign_in<br/>tenanted's hook: no DB selected, so<br/>unknown: 302 /tenant-unknown, apex: 404"]
    flow["login, callback, logout"]
    bsi --> flow
  end

  routes -- "/me, /tenants" --> tr
  routes -- "/auth/*" --> bsi

  span[["server span attributes and child spans<br/>(Partitia::Telemetry::Subscriber)"]]
  sel -. "tenant.subdomain, tenant.handle" .-> span
  tr -. "partitia_tenanted.tenant_resolution.switch<br/>(outcome, handle)" .-> span
  authn -. "partitia_iam.authenticatable.authenticate_request" .-> span
  flow -. "partitia_cognito.sessions_controller.*<br/>partitia_iam.resolution.resolve" .-> span
```

**Not drawn:**
- ActionPack renames the server span to the route (`GET /me`), and ActionView adds render spans.
  ActiveRecord is not traced.
- With `rack_tracing` off there is no server span, `set_span_context` is a no-op, and the
  `partitia_*` spans are roots of their own traces.
- A Tenant row whose database file is missing makes TenantSelector raise
  `TenantDoesNotExistError`.
- `/tenants` also runs `platform_console_guard`, which answers 403 until it is set.
- `/tenant-unknown` skips `switch_tenant`.
- In a single app there is no TenantSelector and no `TenantResolution`. The rest is the same.

## 6. The developer toolchain

`cnfs` is a bash CLI in the cnfs anfs source (`packages/rails/home/.local/bin/cnfs`).
It drives `rails new` with the templates in `~/.config/rails`, and pcm for the services.

### `cnfs new [single|multi] <name>`

```mermaid
flowchart TB
  dev(["cnfs new multi diag"])
  cli["cnfs: recipe = CNFS_APPS_HOME/multi.yml,<br/>else ~/.config/rails/recipes/multi.yml"]
  rn["CNFS_RECIPE=... rails new diag<br/>(railsrc: -m new.rb, which applies main.rb)"]
  main["main.rb, strict: partitia.yml, then the recipe,<br/>then diag.yml beside the app<br/>templates dev (pry, rspec, ruby-lsp) and partitia, ui off"]
  ptrb["partitia.rb<br/>every engine linked by gem-local? (RUBY_LOCAL_GEMS_HOME)<br/>Gemfile: gem partitia-#lt;engine#gt;,<br/>path: partitia_gems/partitia-#lt;engine#gt;<br/>writes partitia.yml, gitignores /config/*.local.yml"]
  bundle["bundle install"]

  dev --> cli --> rn --> main --> ptrb --> bundle

  subgraph after["after_bundle"]
    direction TB
    g1["partitia:tenanted:install<br/>(multi only, first: database.yml still stock)"]
    g2["partitia:support:install"]
    g3["partitia:telemetry:install<br/>bundle add OTel SDK, sentry-rails"]
    g4["partitia:iam:install"]
    g5["partitia:cognito:install<br/>mount /auth, partitia_cognito.yml"]
    me["/me page (iam + cognito)"]
    prep["db:prepare"]
    seed["db/seeds.rb + db:seed (multi only)<br/>provision_platform!, Tenant acme"]
    note["prints how the first sign-in goes"]
    g1 --> g2 --> g3 --> g4 --> g5 --> me --> prep --> seed --> note
  end

  bundle --> g1
  note --> commit["new.rb: git add, commit"]
```

dev has no installer (Q1). In a single app the tenanted and seed steps are skipped. Every
installer is idempotent, so `cnfs template apply partitia` in the app runs the same steps again.

### `cnfs services`, `cnfs server`, `cnfs smoke`

```mermaid
flowchart TB
  subgraph svc["cnfs services"]
    probe["bin/rails runner -e development<br/>gems with metadata partitia.services,<br/>slug, cognito issuer + client_id, tenanted?"]
    ak["authentik (partitia-cognito)<br/>pcm provision authentik --as cnfs/#lt;slug#gt;<br/>redirect=localhost:3000/auth/callback,<br/>redirect_regex for *.localhost (multi)"]
    gt["glitchtip (partitia-telemetry)<br/>pcm provision glitchtip org=partitia project=#lt;slug#gt;<br/>prints DSN"]
    tel["telemetry (partitia-telemetry)<br/>no hook: GRAFANA_DASHBOARDS_DIR<br/>in pcm's containers/telemetry/local.env"]
    cmp["compare ISSUER, CLIENT_ID with the app's config<br/>(public client: no secret stored)"]
    probe --> ak & gt & tel
    ak --> cmp
  end

  subgraph store["secrets store: CNFS_SECRETS_STORE"]
    local["local (default)<br/>config/partitia_telemetry.local.yml<br/>error_dsn, mode 0600, gitignored"]
    fnox["fnox<br/>PARTITIA_TELEMETRY_ERROR_DSN in the app's fnox.toml"]
  end
  gt --> local
  gt -.-> fnox

  server["cnfs server [port]<br/>first free port from 3000, bind 0.0.0.0<br/>fnox exec -- (when fnox.toml) bin/dev or rails server"]
  local --> server
  fnox --> server

  subgraph smoke["cnfs smoke"]
    up["/up 200"]
    login["/auth/login: 302 to the issuer's host<br/>(multi apex: 404)"]
    full["--login: partitia:iam:bootstrap for LINK_TOKEN,<br/>curl through Authentik's flow as akadmin,<br/>callback, /me shows the principal"]
    err["forced Rails.error.report:<br/>GlitchTip event count goes up"]
    trace["Tempo has a trace for service.name"]
    up --> login --> full --> err --> trace
  end
  server --> up
```

Options:
- `cnfs services --down` deprovisions, and removes `error_dsn` from the store.
- `cnfs smoke --login --host acme.localhost` signs in on a tenant. Without `--host`, a multi app's
  apex is checked for its 404.

`cnfs smoke` boots the app under `fnox exec` the same way `cnfs server` does. It reads GlitchTip and
Tempo through `pcm exec`, because Tempo publishes no port.

## 7. How a setting resolves

Every `Partitia::Support::Config` subclass resolves the same way:
- `partitia_iam`, `partitia_cognito`, `partitia_telemetry`, `partitia_urn` and
  `partitia_redaction`;
- the order is anyway_config 2.8's loader registry (`Anyway.loaders` with its Rails overrides);
- each source is deep-merged over the one before, so the lowest box wins;
- `.instance` memoizes the result per class, and `reset_instance!` drops it.

```mermaid
flowchart TB
  def["attr_config defaults<br/>(e.g. otlp_endpoint: pcm's collector, port 4318)"]
  yml["config/#lt;name#gt;.yml<br/>ERB, then the current env's section"]
  lyml["config/#lt;name#gt;.local.yml<br/>development only (use_local_files), merged as is (flat)<br/>gitignored, written by cnfs services (store local)"]
  cred["credentials[:#lt;name#gt;]<br/>config/credentials.yml.enc"]
  lcred["config/credentials/local.yml.enc<br/>development only"]
  env["ENV #lt;NAME#gt;_*, e.g. PARTITIA_TELEMETRY_ERROR_DSN<br/>nested keys with __, values autocast"]
  opt["ejson (ejson on PATH), doppler (DOPPLER_TOKEN)<br/>only when present"]
  coerce["coerce_types<br/>telemetry: rack_tracing :boolean"]
  inst["Config.instance (memoized)"]

  def --> yml --> lyml --> cred --> lcred --> env --> opt --> coerce --> inst

  fnoxx["cnfs server, cnfs smoke: fnox exec --<br/>(when the app has fnox.toml)"] -. "puts PARTITIA_* into the process ENV" .-> env
  conf["#lt;NAME#gt;_CONF=path"] -. "replaces the yml path" .-> yml

  subgraph otel["OTEL_ variables win"]
    o1["OTEL_SERVICE_NAME set:<br/>sdk_service_name is nil"]
    o2["OTEL_EXPORTER_OTLP_(TRACES_)ENDPOINT<br/>or OTEL_TRACES_EXPORTER set:<br/>sdk_traces_endpoint is nil"]
    sdk["config/initializers/opentelemetry.rb<br/>leaves that setting to the OTel SDK,<br/>which reads ENV itself"]
    o1 & o2 --> sdk
  end
  inst --> o1 & o2
```

**Notes:**
- The `.local.yml` file isn't split by environment. A key there is top-level (`error_dsn: ...`),
  and it's read only in development.
- `coerce_types` matters for ENV: without it `PARTITIA_TELEMETRY_RACK_TRACING=0` autocasts to the
  integer `0`, which is truthy.
- Secrets (`hmac_key`, `client_secret`, `error_dsn`) belong in credentials, ENV, the local file or
  fnox, never in the committed yml.
