# IAM progress log

Append-only. Each entry records what shipped, decisions worth flagging, and how
to run it. Newest entries at the bottom.

---

## Plan 001 — Identity Core (tenant-plane): Account · Principal · Credential

**Status:** Complete. **39 examples, 0 failures.** RuboCop clean.

### What shipped

Engine wiring:
- `lib/partitia/iam/engine.rb` — `isolate_namespace Partitia::Iam` + `Partitia::Support.plugins << self`
  so the engine's `db/migrate` joins `Partitia::Support.migrations_paths[:primary]`
  (verified against `partitia-support` source, not assumed — see decisions).
- `app/models/partitia/iam/application_record.rb` — abstract tenant-plane base.
- `lib/partitia/iam.rb` — `Partitia::Iam::Config` (partition/region/hmac_key/account_handle) +
  `Partitia::Iam.configure` + the `Partitia::Iam.current_account_handle` routing seam.

ID / URN / secret support (§4), each with unit specs:
- `Partitia::Iam::Handle` — Crockford base32 minus `0/1/i/l/o/u`, length 8, immutable by
  contract (guarded on owning models).
- `Partitia::Iam::AccessKeyId` — `iam_v1_<handle>_<random><checksum>`, plaintext
  split-to-parse, CRC32→base32 checksum (6 chars). `.generate` / `.parse`
  (never raises) / `.valid?`.
- `Partitia::Iam::Secret` — `iam_secret_<entropy>` plaintext, HMAC-SHA256 digest,
  constant-time `.verify`. NOT bcrypt.
- `Partitia::Iam::Urn` value object + `Partitia::Iam::HasUrn` concern (`to_urn`, `find_by_urn`,
  overridable `urn_id` / `urn_resource_type`).

Models (§5), each `< Partitia::Iam::ApplicationRecord`, with model specs:
- `Partitia::Iam::Account` — singleton (`id=1`), DB `CHECK (id = 1)` + model `id`
  inclusion, `.instance`, `#destroy` raises `ReadOnlyRecord`. Config only — no
  handle column (routing lives on the gem's `Tenant`).
- `Partitia::Iam::Principal` (STI) + `Partitia::Iam::HumanPrincipal` (urn `user`) /
  `Partitia::Iam::MachinePrincipal` (urn `machine`). `has_many :credentials, as: :owner`.
- `Partitia::Iam::Credential` — polymorphic `owner`, generate-on-create access key +
  secret, `secret_digest` stored (never plaintext), plaintext `#secret` shown
  once (cleared on `reload`), `.authenticate(access_key_id, secret) → owner|nil`
  with checksum pre-screen and constant-time compare, urn `access_key`.

Migrations (`db/migrate/`, one `create_*` each, in place): `partitia_iam_accounts`
(CHECK id=1), `partitia_iam_principals` (STI `type` indexed), `partitia_iam_credentials`
(unique `access_key_id`, polymorphic owner index).

Factories (`spec/factories/partitia_iam.rb`): `partitia_iam_account` (routes through `.instance`),
`partitia_iam_human_principal`, `partitia_iam_machine_principal`, `partitia_iam_credential`.

i18n: engine `config/locales/en.yml` under `iam.*`; working `es.yml` example in
`spec/dummy/config/locales/` (host, not engine). Verified both locales resolve.

### Decisions worth flagging

- **`partitia-support` migration-registry API matched §2.3 as assumed.** Registration
  is `Partitia::Support.plugins << self` in the Engine body; the gem's railtie calls
  `set_migrations_paths_from(plugin)` using `plugin.root.join("db/migrate")`.
  No adaptation needed.
- **Test env needed the registry too.** The dummy's `database.yml` only declared
  `migrations_paths` for *development*. With a multi-migration engine,
  `maintain_test_schema!` marked the two older migrations "pending" because the
  test connection couldn't see them (schema load only recorded the latest
  version). Fix: added `migrations_paths: <%= Partitia::Support.migrations_paths[:primary] %>`
  to the **test** section as well. (Single-migration siblings like `chorus`
  don't hit this because there's no older version to appear pending.)
- **`spec/rails_helper.rb` fixes:** it shipped pointing at `../config/environment`
  (engine root, nonexistent) — repointed to `dummy/config/environment`; added
  `require 'factory_bot_rails'`, engine-local `FactoryBot.definition_file_paths`,
  and `FactoryBot::Syntax::Methods`. Mirrors the chorus dummy setup.
- **`.rubocop.yml`:** added `AllCops/TargetRubyVersion: 4.0` (omakase defaulted
  to the Ruby 2.7 parser and false-flagged endless method defs). Matches chorus.
- **Checksum is integrity-of-shape, not a MAC.** CRC32 screens typos/tampering
  before DB/HMAC work; the HMAC secret digest is the real authenticator. ADR 0002
  "open items" (final random length / checksum algorithm) deferred to the
  security pass — round-trip stability + tamper rejection is what's delivered.
- **`Credential#reload` clears the one-time plaintext** so even the originating
  object can't surface `#secret` after a round-trip (stronger shown-once).
- **`Partitia::Iam.current_account_handle` seam** mints+memoises a real handle now (ADR
  0002 §2, never a sentinel) and is documented as the single place that will
  later read from the gem's `Tenant` under tenancy. Not inlined anywhere.

### How to run it

```
# from the engine root (~/spikes/chorus/iam)
bundle exec rspec            # 39 examples, 0 failures
bundle exec rubocop         # clean

# schema is durable/reconciled — after any migration or schema.rb change:
cd spec/dummy
bin/rails db:migrate                          # development; regenerates schema.rb
RAILS_ENV=test bin/rails db:test:prepare      # load schema into the test DB
```

---

## Plan 002 — Root · Identity Links · Resolution · Tenanted Awareness (2026-07-05)

**Status:** Complete (single-tenant scope; one tenanted-integration slice
deferred to Plan 004 — see below). **78 examples, 0 failures** (39 new). RuboCop
clean. Single-tenant regression (the original 39) intact.

### What shipped

- **Piece 1 — Root on `Partitia::Iam::HumanPrincipal`** (ADR 0004). `create_iam_principals`
  edited **in place**: `email`, `root` (null-false default false), plus a
  **partial unique index** `WHERE root` (≤1 root/DB). Model: single-root
  validation (mirrors the index), one-way `root` (demote rejected on update),
  destroy guard (`before_destroy` raises `ReadOnlyRecord`). Machines validated
  never-root. `Partitia::Iam::Credential` rejects a root owner (root holds no keys).
- **Piece 2 — `Partitia::Iam::IdentityLink`.** New model + migration: `(issuer, subject)`
  unique per DB, `belongs_to :principal`, validated human-only. The IdP `subject`
  lives only here. `HumanPrincipal has_many :identity_links`.
- **Piece 3 — Link token.** `link_token_digest` + `link_token_expires_at` on
  `partitia_iam_principals` (in place). `HumanPrincipal#issue_link_token!` /
  `.find_by_link_token` / `#consume_link_token!`, reusing `Partitia::Iam::Secret`
  (HMAC digest stored, plaintext returned once).
- **Piece 4 — `Partitia::Iam::Resolution`** (ADR 0004 contract). `Partitia::Iam::Assertion` value
  object + `Partitia::Iam::Resolution.resolve(assertion:, policy:, link_token:) → Result`.
  `:jit` (create-on-unknown) / `:invite_only` (known, or bind+consume a valid
  link token) / fail-closed on unknown/absent policy. Plain-string failure
  vocabulary. No tenancy awareness.
- **Piece 5 — Tenanted awareness (guarded).** `Partitia::Iam::TenantSeeder.call(context)`
  (one code path: `Account.instance` + root from `context.owner_email` + token),
  `Partitia::Iam::RootRecovery.reset!`, and the `Partitia::Iam.current_account_handle` tenanted
  branch. Registered into `Partitia::Tenanted.after_provision` from the engine, guarded
  by `defined?(Partitia::Tenanted)`.
- **Piece 6 — `Partitia::Iam::Current` + `Partitia::Iam::Authenticatable`.** Session → `Current.user`
  per request (stale id → anonymous), `require_authentication` (401 default),
  `session_key` config (default `:partitia_iam_user_id`).

### Decisions worth flagging

- **Bootstrap-token surfacing:** `Partitia::Iam::TenantSeeder.last_bootstrap_token` (a class
  accessor). Provisioning runs synchronously inside `create_tenant`, so the
  caller reads it immediately after. Spike-simple; a *concurrent* provisioner
  would race — swap for a per-call sink if that becomes real. (Piece 5.1.)
- **Current-tenant accessor verified, not guessed** (Piece 5.2 instruction):
  `ActiveRecord::Tenanted.connection_class.current_tenant` (activerecord-tenanted
  0.7.0 — subtenants delegate it). The current-tenant string IS the routing
  handle after Plan 001 WS3, so `current_account_handle` returns it directly.
  Precedence: explicit host pin › active tenant handle › single-tenant
  mint+memoise. Single-tenant path unchanged.
- **after_provision registration is reload-safe.** Registered once at
  `after_initialize` (not `to_prepare`, which would duplicate on reload) as a
  lambda that resolves `Partitia::Iam::TenantSeeder` lazily (so a code reload never leaves
  a stale class reference). iam does not depend on partitia-tenanted — one-way
  inverted touchpoint.
- **`Partitia::Iam::Resolution` placement:** `app/services/partitia/iam/resolution.rb` (autoloaded
  `Partitia::Iam::Resolution`) — a stateless domain service, not an AR model. `Result` is a
  nested `Struct`; `Partitia::Iam::Assertion` is a sibling value object in `app/models`.
- **Link-token lookup is by HMAC digest** (deterministic column lookup), not a
  per-row secure_compare: the plaintext token is never stored and cannot be
  derived from the digest, so the digest column is a safe index. Expiry filtered
  in the same query.
- **Stale committed `spec/dummy/db/schema.rb`** (v120003) was loaded in
  preference to the migrations, masking the in-place edit to 120002 (the same
  trap as Plan 001). Deleting `schema.rb` + the sqlite file and running
  `db:migrate` from empty ran all four migrations and regenerated the dump. The
  dummy schema dump is now rubocop-excluded.

### Piece 5 deferral (sanctioned by the plan)

The plan allows deferring Piece 5's **tenanted** specs if they'd require standing
up a multi-tenant dummy. They would — and that dummy is exactly what **Plan 004**
builds in `partitia-tenanted`'s `spec/dummy`. So all Piece 5 **code** shipped and is
tested as far as single-tenant allows (`TenantSeeder.call` and `RootRecovery`
driven directly with a context double; `current_account_handle` single-tenant
regression; registration proven inert without `Partitia::Tenanted`). Deferred to Plan
004: creating a real `Tenant` seeds exactly one `Account` + root with a live
token inside that tenant's DB and not another's; a seeder raise rolls back the
`Tenant`; `current_account_handle` returns the tenant handle in-context. iam's
own dummy stays single-tenant (the regression guard for the no-tenancy promise).

### How to run it

```
cd ~/spikes/chorus/iam
bundle exec rspec            # 78 examples, 0 failures
bundle exec rubocop          # clean

# after an in-place migration edit, rebuild from empty (schema.rb is loaded in
# preference to migrations, so a plain db:migrate won't re-run an edited one):
cd spec/dummy && rm -f db/schema.rb storage/test.sqlite3
RAILS_ENV=test bin/rails db:migrate
```

## Plan 005 — Diagnostic logging

Layered level-graded `logger` lines onto the already-instrumented auth seams
(`Resolution`, `Credential`, `HumanPrincipal`, `IdentityLink`, `TenantSeeder`,
`Authenticatable`), following the **`logging` skill**'s level policy
(debug=flow, info=change, warn=anomaly, error=fault) and mandatory block form.
The service objects `Resolution` and `TenantSeeder` gained an explicit
`include Partitia::Support::Logging`; models and the concern already had `logger` via
the railtie.

- **Tag is `partitia_iam` by construction.** `component_tag` keys off the first
  namespace segment, so every line — model, service, or concern — tags
  `partitia_iam`. The one subtlety is `Partitia::Iam::Authenticatable`: inside the concern
  `self` is the *host* controller, so the default `logger` would tag under the
  host app. It memoizes a logger built from `Authenticatable.name`
  (`Partitia::Support::Logging.build_for` → `partitia_iam`), the same reason
  `instrument_iam` pins the event name. A spec asserts the concern line lands
  under `[partitia_iam]`.
- **Redaction (spec-enforced).** No bootstrap/link token, credential secret,
  IdP `subject`, or email ever appears in a line — ids and issuer hosts only.
  The redaction specs feed known sentinel values through issue/consume/
  authenticate/resolve and assert their absence from the joined output.
- **Raise verbosity:** `Partitia::Support::Logging.levels["partitia_iam"] = :debug` in a
  console/initializer to see the full flow trace; the default floor `:info`
  shows only the mutation ledger (principal created, identity link bound).
- **WS3 (verified, no code):** `Partitia::Support::Logging.bridge_to_spans` is left at
  its default (**off**) — the log→span bridge stays opt-in, a telemetry-era
  decision. No `instrument(...)` payload or block shape changed; logging rides
  *alongside* the existing spans (every `event[:outcome] = …` is untouched).

`bundle exec rspec` → 101 examples, 0 failures (Docker stopped). `bundle exec
rubocop` → clean.

## Plan 006 — Config adoption (Partitia::Support::Config)

**Config inventory (WS1).** `Partitia::Iam::Config` (`lib/partitia/iam.rb`) held all config DATA:
`partition`, `region`, `hmac_key` (**secret**), `account_handle`, `session_key`
— previously a plain class with `attr_accessor` + `ENV.fetch("PARTITIA_IAM_HMAC_KEY", …)`.
No inversion slots in iam. `current_account_handle` is routing *logic*, not
config, and is untouched.

**Migrated (WS2).** `Partitia::Iam::Config` is now a `Partitia::Support::Config` subclass
(`config_name :partitia_iam`), so every value resolves `config/partitia_iam.yml` →
`credentials.partitia_iam` → `ENV["PARTITIA_IAM_*"]`. Same keys, same defaults:
`partition:"cnfs"`, `region:""`, `hmac_key:DEFAULT_HMAC_KEY`,
`session_key::partitia_iam_user_id`, `account_handle:nil`. `DEFAULT_HMAC_KEY` stays
flagged **NON-SECRET, dev/test only**; production sources the real key via
`PARTITIA_IAM_HMAC_KEY` / `credentials.partitia_iam.hmac_key` (same env var as before → no
deploy-behavior change).

**Read API preserved.** `Partitia::Iam.config` now returns `Config.instance`;
`Partitia::Iam.config.hmac_key`, `Partitia::Iam.config.account_handle = …`, and
`Partitia::Iam.configure { |c| … }` all keep working, so the gem, its specs, and app
initializers are unchanged in shape. The single-tenant `account_handle`
mint+memoise survives (specs green).

**Generator (WS5).** `install/templates/partitia_iam.rb` no longer emits
`c.hmac_key = ENV.fetch(…)`; the chain resolves it. The secret is documented to
`credentials.partitia_iam.hmac_key` / `PARTITIA_IAM_HMAC_KEY` (never inlined); non-secret tunables
are commented `Partitia::Iam.configure` overrides.

**Green.** `spec/partitia/iam/config_spec.rb` added (defaults, ENV override for the
secret + partition, `Partitia::Iam.config` API). `bundle exec rspec` → 106 examples, 0
failures. `bundle exec rubocop` → clean.

---

## Plan 008 — Telemetry: span enrichment + Grafana dashboards

**Status:** WS1 complete. **107 examples, 0 failures.** RuboCop clean.
Docker/podman not required for the specs (notification-layer only).

### What shipped (WS1 — iam spans)

- **`partitia_iam.credential.issue`** now carries a bounded **`owner_type`** dimension
  (`"HumanPrincipal"` / `"MachinePrincipal"`, via `owner.class.name.demodulize`)
  so credential issuance can be split by principal kind on a dashboard. Never the
  key or secret. (`app/models/partitia/iam/credential.rb`.)
- Every other iam hot-path span was already compliant post-Plan-005 and left
  unchanged: `resolution.resolve` (policy+outcome), `resolution.provision_jit`
  (issuer — id/host only, never subject/email), `credential.authenticate`
  (outcome), `human_principal.issue_link_token` (root:), `authenticate_request`
  (authenticated:), `authz_gate` (outcome).

**`subject` removed and why.** No iam span attached `subject`/`email`/
`principal_id`/`access_key_id`/session-id/full-URL (audited). The live
`subject` PII+cardinality bug lived in partitia-cognito's `oidc.verify` — fixed
there. iam's `provision_jit` deliberately keeps only `issuer` even though the
assertion carries email/name.

**The cardinality/PII guard now reads the redaction config.** New guard example
in `spec/partitia/iam/instrumentation_spec.rb` drives every `partitia_iam.*` span and asserts
`payload.keys & Partitia::Support::RedactionConfig.sensitive_fields == []`. The
forbidden set is **read from Plan 006's config, not hard-coded** — a new
sensitive field added to the config is enforced across all iam spans
automatically. Plus an `owner_type`-present assertion on the issue span.

### How to run

`cd gems/iam && bundle exec rspec` → 107 examples, 0 failures;
`bundle exec rubocop` → clean.

### Dashboards (WS2) & how to point the stack at them

CNFS Grafana dashboards live in
`~/spikes/chorus/storage/telemetry/dashboards/cnfs/`
(`cnfs-auth-overview.json`, `cnfs-operation-latency.json`; stable uids
`cnfs-auth-overview` / `cnfs-operation-latency`). They query the **Tempo**
datasource (uid `tempo`) with TraceQL-metrics against `partitia_iam.*` span names +
the WS1 dimensions. Point the stack at them by setting **`DASHBOARDS_DIR`** in
`services/telemetry/.env` (gitignored; `.env.example` documents the value) to
that store, then `podman compose up -d`. Both provision into the "cnfs" Grafana
folder on boot.

### WS3 — live E2E (complete) + two findings the live run forced

The earlier `single` boot failure was **not** a missing dep — it was a leaked
`RUBYLIB` injecting `rest_cli`'s path. `unset RUBYLIB && bin/rails …` boots
cleanly. Drove real flows (resolution jit-new/jit-known/invite-only-unknown,
credential issue+authenticate, and the cognito provider against a **live
Authentik** at `:9000`), `force_flush`ed, and inspected Tempo. Results:

- **Enrichment reaches Tempo and the PII fix holds in production.** Verified
  attribute values on real spans: `resolve.outcome`=success/unknown_identity,
  `resolve.policy`=jit, `provision_jit.issuer`=…, `credential.issue.owner_type`=
  MachinePrincipal, `verify.outcome`=malformed. A TraceQL search for any cnfs
  span carrying a `subject` attribute returns **0** — `subject` is gone.
- **Finding 1 — attribute keys are namespaced by the full event name.** The
  `partitia-telemetry` bridge sets `span.set_attribute("#{event_name}.#{key}", …)`
  (intentional, tested). So the queryable key is
  `span."partitia_iam.resolution.resolve.outcome"`, **not** `span.outcome`.
- **Finding 2 — cognito span names carry the concrete provider subject.** The
  registered provider is `Partitia::Cognito::Providers::Authentik < Oidc`, so real
  spans are `partitia_cognito.authentik.*`, not `…oidc.*`.

The plan assumed bare `span.outcome` and `partitia_cognito.oidc.*`; **the dashboards
were corrected to the verified reality** (fully-qualified attribute keys +
`authentik` span names) and **every panel query re-validated against live data**
(HTTP 200, real series). Both findings are provider/bridge behavior outside this
plan's WS1 scope — flagged for architecture (attribute namespacing couples every
query to the exact span name; provider-in-name means dashboards are per-provider).
