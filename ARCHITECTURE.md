# Architecture

**Status: Agreed (2026-10-22).** `pt engine check` (D0) is to enforce the contract below. The
decisions behind it, with the evidence from the earlier apps, are at the end.

Partitia is a family of Rails engines that apps compose. Each engine is a gem in this repo
(`<dir>/partitia-<dir>.gemspec`), developed against a `spec/dummy` app, and installed into an
app by its own generator.

## Layers

| Layer | Engines | Job |
|---|---|---|
| Base | support, dev, telemetry | What every engine and app uses: config, logging, instrumentation, the plugin registry, console tooling, the bridge to OpenTelemetry |
| Identity | tenanted, iam, cognito | Who is asking and in which tenant: tenancy (optional), principals and authorization, sign-in through an IdP |
| Presentation | ui (shelved) | Shared Phlex/RubyUI components, when engines start duplicating view code |

**Dependencies point down or sideways, never up.** Base never depends on identity. support depends
on no sibling. Within a layer an engine may integrate with another only optionally (below).

```mermaid
graph BT
  support
  dev
  telemetry --> support
  tenanted --> support
  iam --> support
  cognito --> support
  ui
  iam -. optional .-> tenanted
  cognito -. host wires .-> iam
```

## The engine contract

An engine meets every rule, or the exception is written here with its reason.

### 1. Naming

- Gem `partitia-<name>`, module `Partitia::<Name>`, require `partitia/<name>`. `Iam`, `Ui`: no
  acronym inflections (they change the host's inflections).
- No top-level constants, with one exception: the Phlex/RubyUI host namespaces `Views`,
  `Components` and `RubyUI`, which those libraries expect at the top of the app (Q4). Tables
  `partitia_<name>_*`; events, spans and log tags
  `partitia_<name>.*`; config `partitia_<name>` (`config/partitia_<name>.yml`,
  `PARTITIA_<NAME>_*`); generators `partitia:<name>:<generator>`; rake `partitia:<name>:*`.

### 2. Dependencies

- Every sibling the code needs at runtime is a gemspec dependency.
- An optional sibling is detected with `defined?(Partitia::<Name>)`, never required, and each
  integration is listed in the engine's README ("With partitia-tenanted: …").
- Cross-engine wiring the engine cannot know goes through a hook the host or the other engine
  fills (`Partitia::Tenanted.after_provision`, `Partitia::Cognito.identity_resolver`), never a
  constant reference across engines.

### 3. Registration

- Every engine (a `Rails::Engine`; the registry takes nothing else) registers itself, whether
  or not it has tables or views today (Q6). The railtie gems (support, dev, telemetry) have
  nothing to register:
  `Partitia::Support.plugins << self` in its engine class. That is how its migrations reach the
  app (`Partitia::Support.migrations_paths`, per scope) and its views and components reach
  Tailwind (`Partitia::Support.source_paths`).
- **Exempt: dev** (Q1). It is console tooling, loaded only by `rails console`: no registration,
  config, install generator, tenancy or services (§3–§6, §9). Engines still add their console
  helpers to it (`Partitia::Dev.console`, behind `defined?(Partitia::Dev)`); the earlier apps
  were driven mostly from the console, so helpers like switching tenant are worth the most.

### 4. Configuration

- Settings live in one `Partitia::Support::Config` subclass, `config_name :partitia_<name>` (an
  engine with no settings has none; callables are not settings, see below). Values resolve from
  `config/partitia_<name>.yml`, then credentials, then `PARTITIA_<NAME>_*`; nothing reads ENV
  directly. One exception: telemetry steps aside for the standard `OTEL_*` variables when they
  are set, as OpenTelemetry's own convention says.
- Secrets only from credentials or ENV. A development fallback is allowed only when it is
  labelled not-a-secret and production refuses it.
- Endpoints default to the pcm service a developer runs (`stack/telemetry`, `stack/authentik`,
  `stack/glitchtip`), so a generated app works against `pcm up` with no edits. No endpoint, DSN
  or client secret is written into the app as a literal.
- Callables the host must provide (resolvers, guards) are module-level slots that **fail loudly
  or deny** when unset, never silently allow.

### 5. Install generator

- `partitia:<name>:install` exists, even when it has little to do.
- **Idempotent:** a second run changes nothing and asks nothing. Every write is guarded.
- **Never overwrites a host file wholesale** (`force: true` on `template`, `create_file`,
  `copy_file` or `directory`); it injects into it, or stops and says what to change. `force:` on
  `insert_into_file` is fine: it only lets the same line into a file twice. One exception: a file
  that is still exactly what `rails new` wrote may be replaced (tenanted's `database.yml`); the
  line says so with `# §5: stock file only`, and anything else stops with a non-zero exit and
  the change to make.
- Migrations reach the app through the registry (`migrations_paths` in `database.yml`), not by
  copying (Q3). The generator wires **every environment** (development, test, production), and
  every plane the engine has (a global plane is registered by the engine, never by a line in
  the app).
- What a request carries that is secret (OAuth `code` and `state`, tokens) is added to
  `filter_parameter_logging`.
- It ends by printing what the host still has to do, if anything, and the entry points it
  added (paths such as `/auth/login`).
- Migrations are edited in place only before the first release; after it, a change is a new
  migration.

### 6. Tenancy

- Works in a single-tenant app and a multi-tenant one with no code change in the engine.
  Multi-tenant behavior switches on when partitia-tenanted is present.
- Tenant-plane tables in `db/migrate`; global-plane tables in `db/global_migrate`; the reserved
  platform database holds identity only (ADR 0003).

### 7. Observability

- Models and controllers log and instrument through `Partitia::Support::Logging` and
  `Instrumentable` (the support railtie injects them). Events are
  `partitia_<name>.<class>.<verb>`.
- No payload key is in `Partitia::Support::RedactionConfig.sensitive_fields`, and the bridge to
  spans drops any that is (telemetry depends on support for this, Q2).
- telemetry owns the app's observability settings in one config class: service name, OTLP
  endpoint and the error tracker's DSN (GlitchTip, through `sentry-rails`), each defaulting to the
  pcm service. Installing it without its generator must not be a silent no-op.
- Spans and dashboards are named for the code, not the app (ADR 0007): the app is
  `service.name`.

### 8. Views

- Phlex classes that use RubyUI components; no ERB. The engine lists the RubyUI components it
  uses, and its installer adds them to the app. The app's Phlex/RubyUI setup (namespaces,
  `Components::Base`, design tokens) comes from the app template (D5), modelled on the earlier
  `fudge` app. Until that template exists (D5) the existing ERB views stay; converting them is
  D5's, not D3's.
- Engine controllers inherit the host's `ApplicationController` unless isolation is the point
  (cognito's broker), which is then stated.

### 9. Services

- An engine that needs an external service names the pcm service in its gemspec metadata
  (`spec.metadata["partitia.services"] = "telemetry"`), so `pt services` can start what an app
  needs.

### 10. Tests and CI

- `spec/dummy`, with `ActiveRecord::Migration.maintain_test_schema!` in `spec/rails_helper.rb`.
- `required_ruby_version` in the gemspec; lockfile platforms `arm64-darwin`,
  `x86_64-linux-gnu`, `aarch64-linux-gnu`.
- An entry in both CI matrices.

## Where each engine stands

Gaps against the contract, from the code on 2026-10-22. These become D3's work list.

| Engine | Gaps |
|---|---|
| support | None (D3 done). A railtie, not an engine, so §3, §6 and §8 don't apply |
| dev | Exempt from §3–§6 and §9 (Q1). Has specs now. `require "pry-byebug"` runs whenever the gem loads, not only in the console; no public `Partitia::Dev.reset!` |
| telemetry | Not yet installed into a fresh app (D3). The GlitchTip DSN is a manual step until pcm provisions GlitchTip (D4) |
| tenanted | Views are ERB (§8, D5). `db:migrate:global` is in the `db:` namespace, not `partitia:tenanted:` (§1). `config.partitia_tenanted.trace` is an observability setting that may belong in telemetry's config (§4, Q2). Migration status also lists activerecord-tenanted's `development-tenant` template database |
| iam | Layout is ERB (§8, D5). README is the Rails stub, so the integrations list (§2) is missing |
| cognito | When the IdP is unreachable, `/auth/login` is a bare 500 (`ECONNREFUSED`); it should be a clear "identity provider unavailable" page (503). Production has no issuer default and fails at the first discovery call rather than at boot (§4). The live Authentik spec has not run against pcm's Authentik |
| ui | Shelved. No install generator (§5): `partitia:ui:install` is where D5's app setup (Phlex/RubyUI namespaces, the host's `app/components/ruby_ui`, tokens) belongs |

## Wiring an app today

Proven on two fresh `rails new` apps (2026-10-22): each generator run twice, the second
changing nothing; both databases migrated; served with `pt server` on 0.0.0.0. D5 turns these
steps into `pt new`.

**Single-tenant** (support, telemetry, iam, cognito): add the gems, then
`partitia:support:install` (the registry line in every environment's primary database),
`partitia:telemetry:install`, `partitia:iam:install`, `partitia:cognito:install` (mounts
`/auth`, writes `config/partitia_cognito.yml`, filters `code`/`state`); `db:prepare`. Each
prints what is left: production secrets, `include Partitia::Iam::Authenticatable` where
sign-in is required, the Authentik provider and client secret.

**Multi-tenant** (+ tenanted): `partitia:tenanted:install` **first**, while `database.yml` is
still stock (it writes the global and tenant planes; support's installer then finds them
wired), then the others as above; `db:prepare`; `Partitia::Tenanted.provision_platform!`, then a
`Tenant` per tenant (iam seeds each tenant's account and root on creation). `acme.localhost`
runs in acme's database; an unknown subdomain redirects to `/tenant-unknown`; `/tenants`
answers 403 until `platform_console_guard` is set. Signing in on a tenant's subdomain needs
the wiring in `tenanted/spec/dummy/config/initializers/identity.rb` (the callback must run in
the tenant's database), which D6 settles.

## Decisions (2026-10-22)

The review answered these, checked against the four apps built on the earlier gems (`single`,
`multi`, `factory`, `fudge`).

- **Q1 — dev is exempt** from registration, config, install, tenancy and services. The apps were
  driven mostly from the console (single's log: a dozen web-console sessions; multi's only
  activity: console loads of `Tenant`), so engines keep adding console helpers to it.
- **Q2 — telemetry depends on support** and owns the app's observability settings: service
  name, OTLP endpoint, error-tracker DSN. In the apps the OpenTelemetry endpoint came from raw
  `OTEL_*` variables, the GlitchTip DSN was a literal in an initializer, and multi had the gems
  with no initializer, so it silently exported nothing.
- **Q3 — migrations through the registry.** Every app pointed `database.yml` at the engines'
  migration folders and none copied one; engine migrations ran straight from the gems. The gaps
  were that only development was wired, and multi registered the global plane by hand, pointing
  at a folder it did not have.
- **Q4 — `Views`, `Components`, `RubyUI` may be top-level.** fudge, the UI experiment, shows the
  setup that needs them.
- **Q5 — tenanted keeps drawing its routes into the app.** No app exercised it; the multi demo
  (D6) is the test.
- **Q6 — every engine registers**, cognito included.
- **Q7 — authorization (Pundit) is later**, when the demo needs it. No app used it.

Also from the apps, now rules above: the OAuth `code` and `state` were in single's log (§5,
filtering); single's log shows guesses at the login path before `/auth/login` (§5, print entry
points); single pinned the URN partition to the old `cnfs` placeholder (ADR 0007).
