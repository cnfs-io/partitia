# partitia-cognito — progress

Append-only. Each entry records what shipped, decisions worth flagging, and how
to run it. Newest at the bottom.

---

## Plan 003 — Auth Broker · Provider Registry · Authentik (2026-07-05)

**Status:** Complete (WS1–WS5). **26 examples, 0 failures** with Docker stopped;
RuboCop clean. WS4 (Docker harness) authored to spec but not container-booted in
this session — see the caveat below.

### What shipped

- **WS1 — Engine + config.** Converted the skeleton railtie to a full
  `Partitia::Cognito::Engine` (`isolate_namespace`). RSpec + a **lean, DB-less
  `spec/dummy`** that mounts the engine at `/auth`. Config slots
  (`Partitia::Cognito.*`): `identity_resolver` (no default — raises a helpful
  `ConfigurationError` if used unset), `policy_resolver` (default
  `->(_) { :invite_only }`, fail-closed), `session_key` (`:partitia_iam_user_id`),
  `provider` (no default — raises), `after_sign_in_path` / `after_sign_out_path`
  (default `/`, string-or-callable).
- **WS2 — Assertion + providers.** `Partitia::Cognito::Assertion` (immutable, exactly
  the ADR 0004 fields). `Providers::Base` duck + `VerificationError`.
  `Providers::Registry` (register/fetch by name). `Providers::Oidc` — discovery
  + JWKS fetch/cache (refetch-on-unknown-kid), ID-token verification via the
  `jwt` gem (RS256 pinned, iss/aud/exp + nonce), auth-code + PKCE (S256).
  `Providers::Authentik < Oidc` (intentionally near-empty). `Pkce` helper.
- **WS3 — SessionsController + routes.** `GET /auth/login` (stash
  state/nonce/PKCE verifier + optional `link_token`, redirect to IdP),
  `GET /auth/callback` (validate state, exchange, verify, `policy_resolver`,
  `identity_resolver`, establish session with `principal.id`), `DELETE
  /auth/logout`. Failures redirect with an i18n flash keyed by `failure_reason`;
  claim contents never leak.
- **WS4 — Authentik dev harness (dev-only).**
  `spec/dummy/docker/authentik/compose.yaml` (Postgres 16 + Redis 7 + server +
  worker, healthchecked, named Postgres volume, secrets via gitignored `.env` +
  committed `.env.example`), executable `bin/authentik`
  (`up|down|status|logs|reset`, health-poll then foreground logs), and an opt-in
  `authentik:` line in `spec/dummy/Procfile.dev`.
- **WS5 — Specs (no container/network).** WebMock OIDC harness
  (`spec/support/oidc_helpers.rb`: RSA keypair, stubbed discovery/JWKS/token,
  signed ID tokens). Verification matrix on `Oidc#verify`; flow request specs
  (provider stubbed at the HTTP layer, `identity_resolver` stubbed at the slot);
  config + registry + PKCE units; one `:authentik` live spec excluded by default.

### Decisions worth flagging

- **`jwt` is a runtime gemspec dependency** (the broker needs it in production);
  `webmock` is Gemfile `:test` only. jwt resolved to **3.2.0** — verified its
  JWK API (`JWT::JWK.import(hash).public_key`, string-keyed JWKS) before
  building on it. RS256 is **pinned** in `Oidc::ALGORITHMS` — the token header's
  `alg` is never trusted (defeats alg:none / algorithm-confusion).
- **Lean, DB-less dummy (deviation from iam's dummy).** The broker owns no tables
  and stores no identities, so the dummy loads only Action Controller/View — no
  `active_record`, no asset pipeline (no propshaft/tailwind/importmap). It is
  still "RSpec + spec/dummy mounting the engine," just without the parts a broker
  has no use for. Fewer moving parts, no schema to maintain.
- **Skeleton fixes.** The generated `Gemfile` pointed its path gems at
  `../partitia-support` / `../partitia-dev`; the real dirs are `../support` / `../dev` —
  fixed. Removed the unused `railtie.rb`.
- **Authentik pinned tag `2024.10.5`, host port `9000`** (health at
  `/-/health/ready/`). Never `:latest`.
- **`:authentik` tag convention.** The single live-container spec is tagged
  `:authentik` and excluded via `config.filter_run_excluding :authentik` in
  `rails_helper`. The default suite passes with Docker stopped (WebMock disables
  real net connections). Run the live one with `--tag authentik` +
  `AUTHENTIK_ISSUER=...`.

### Caveat — WS4 not container-verified this session

The compose stack and `bin/authentik` were authored to the plan but **not booted
against Docker** in this session (no Docker runtime exercised here). The DoD's
"boots Authentik healthy via bin/authentik (verified once)" step is
**outstanding** — someone should run `cp .env.example .env` (fill secrets) then
`bin/authentik up` once and confirm health before relying on it. The default
test suite does not depend on this (it is fully stubbed).

### How to run it

```
cd ~/spikes/chorus/cognito
bundle exec rspec        # 26 examples, 0 failures (Docker stopped)
bundle exec rubocop      # clean

# live IdP (opt-in, needs Docker):
cp spec/dummy/docker/authentik/.env.example spec/dummy/docker/authentik/.env  # fill secrets
bin/authentik up
AUTHENTIK_ISSUER=http://localhost:9000/application/o/<slug>/ bundle exec rspec --tag authentik
```

## Plan 005 — Diagnostic logging

Layered level-graded `logger` lines onto the broker's auth seams
(`SessionsController` + `Providers::Oidc`), following the **`logging` skill**'s
level policy (debug=flow, info=change, warn=anomaly, error=fault) and mandatory
block form. `SessionsController` already had `logger` (railtie → gem
`ApplicationController`); the providers are POROs, so `Providers::Base` gained an
explicit `include Partitia::Support::Logging` and `Oidc` inherits it.

- **Tag is `partitia_cognito` by construction — including the nested provider.**
  `Providers::Oidc` sits three namespaces deep, but `component_tag` keys off the
  first segment (`Partitia::Cognito`), so its lines still collapse to the flat
  `partitia_cognito` tag — matching the component the hand-rolled provider
  `instrument` already pins. A spec asserts a nested-provider line lands under
  `[partitia-cognito]` (the regression guard: no `partitia/cognito/providers` tag can
  occur).
- **Level discipline.** Expected security verdicts (state mismatch, id-token
  verification failure, JWKS unknown-`kid` refetch) are **`warn`**, not error;
  only genuine HTTP faults (IdP non-2xx on discovery/JWKS/token) are **`error`**.
- **Redaction (spec-enforced).** No `id_token`, authorization `code`,
  `code_verifier`, `client_secret`, or claim contents in any line. GET faults
  log the full (non-secret) discovery/JWKS URL; the token **POST** logs host +
  status only, never the form body. Specs push sentinel `id_token`/`code`/
  `client_secret` values through the callback + provider paths and assert
  absence from the joined output.
- **Raise verbosity:** `Partitia::Support::Logging.levels["partitia_cognito"] = :debug` to
  watch the full arc (login start → callback → state validated → token exchange
  → verify → resolving → sign-in ok); the default floor `:info` shows only
  `sign-in ok` / `sign-out`.
- **WS3 (verified, no code):** `Partitia::Support::Logging.bridge_to_spans` left at its
  default (**off**). No `instrument(...)` payload or block shape changed —
  logging rides alongside the existing spans (`event[:status]`,
  `event[:rotated]`, `event[:outcome]`, `event[:issuer]/[:subject]` untouched).

`bundle exec rspec` → 44 examples, 0 failures (Docker stopped). `bundle exec
rubocop` → clean on all changed files; the sole remaining offense is a
pre-existing parse error in the `install` generator's config **template**
(out of scope per the plan, unmodified here).

## Plan 006 — Config adoption (Partitia::Support::Config)

**Config inventory (WS1).** Two kinds of setting lived in `partitia-cognito`:
- **Provider connection config = DATA** — `issuer`, `client_id`,
  `client_secret` (**secret**), `scopes`. Previously hand-plucked from ENV
  (`ENV.fetch("AUTHENTIK_*")`) as constructor kwargs in the initializer/template,
  and — worse — inlined as a plaintext `client_secret` literal in Single.
- **Inversion SLOTS = callables** — `identity_resolver`, `policy_resolver`,
  `provider`, `session_key`, `after_sign_in_path`, `after_sign_out_path`. These
  stay as module accessors with fail-loud semantics (**not** migrated;
  `session_key` reviewed and kept as a slot to match `Partitia::Iam`'s).

**Migrated (WS2).** New `Partitia::Cognito::Config < Partitia::Support::Config`
(`config_name :partitia_cognito`, `lib/partitia/cognito/config.rb`) carries the four
connection values: `issuer`/`client_id`/`client_secret` (no defaults) and
`scopes` (default `%w[openid email profile]`). Resolves
`config/partitia_cognito.yml` → `credentials.partitia_cognito` → `ENV["PARTITIA_COGNITO_*"]`.
`partitia_cognito.rb` now `require`s it (partitia-support is already a path gem in the
Gemfile). The module slots are unchanged — `spec/partitia/cognito/config_spec.rb`
(slots) still green; `spec/partitia/cognito/provider_config_spec.rb` added (data).

**Generator (WS5).** `install/templates/partitia_cognito.rb` now builds the provider
from `Partitia::Cognito::Config.{issuer,client_id,client_secret,scopes}` — no
`ENV.fetch`, no secret literal; the `install_generator.rb` post-install `say`
points at `config/partitia_cognito.yml` (non-secret) and `credentials:edit` /
`PARTITIA_COGNITO_CLIENT_SECRET` (secret). Slots left exactly as-is.

**⚠️ SECRET ROTATION REQUIRED (WS4 — Roberto action, not automatable here).**
Single's `config/initializers/partitia_cognito.rb` previously contained a **real,
plaintext Authentik `client_secret`** (128-char literal). It was **relocated**
to `credentials.partitia_cognito.client_secret` (verified round-trip) so login keeps
working, and removed from the initializer. But a secret committed inline is
**compromised** — relocation is necessary, not sufficient. **The value must be
regenerated in Authentik** (OAuth2/OIDC provider) and the new secret written to
credentials; this cannot be done from here.

**Green.** `bundle exec rspec` → 47 examples, 0 failures. `bundle exec rubocop`
→ clean on all changed files; the pre-existing template parse artifact (Ruby-2.7
parser vs the unchanged `identity_resolver` hash-shorthand; gem sets no
`TargetRubyVersion`) remains — not introduced here.

---

## Plan 008 — Telemetry: span enrichment + Grafana dashboards

**Status:** WS1 complete. **51 examples, 0 failures.** RuboCop clean.
Notification-layer specs; WebMock OIDC harness; no container/network.

### What shipped (WS1 — partitia-cognito spans)

**`subject` removed (live PII + cardinality bug — WS1.1).**
`Partitia::Cognito::Providers::Oidc#verify` set `event[:subject] = assertion.subject`.
The IdP `sub` is per-user: PII **and** a span-metric series explosion. Removed as
a span attribute (`issuer` — a bounded host — kept). Audited the whole gem: no
other span attached `subject`/`email`/`principal_id`/`access_key_id`/session-id/
token/full-URL. Per-request subject visibility, if ever needed, belongs on a log
line, never a metric dimension.

**Closed outcome vocabularies (WS1.3).**
- `oidc.verify` — rescue moved **inside** the instrument block so the outcome
  lands on the span before the re-raise marks it errored (failures stay countable
  by reason). `"verified"` on success; a new `verify_failure_reason` maps
  exceptions to a **closed** set — `expired` / `bad_signature` / `malformed`
  (JWT subtypes) and `nonce_mismatch` / `unknown_kid` (our VerificationError),
  fallback `invalid`. Never the raw `e.message`.
- `oidc.exchange_code` — `outcome` `"ok"` / `"failed"`; never code/secret/body.
- `oidc.http` — replaced the unbounded **`url`** attribute with a bounded
  **`endpoint`** label (`"discovery"` / `"jwks"` / `"token"`), threaded from each
  caller. `method` + `status` kept; the debug log line still names the host.
- `oidc.signing_key` — `kid` (bounded) + `rotated` kept as-is.
- `sessions_controller.callback` already carried `outcome`
  (`success`/`invalid_state`/`verification_failed`/resolver `failure_reason`) +
  `policy` — left unchanged; `login_start` keeps its `has_link_token` boolean.

**Hand-rolled instrument migrated (WS1.4).** `Providers::Base` now
`include Partitia::Support::Instrumentable`; the hand-rolled `instrument` (and its
stale `component_tag` comment) are gone. Verified emitted names are **identical**
(`partitia_cognito.oidc.<verb>`): `component_tag("Partitia::Cognito::Providers::Oidc")` →
`partitia_cognito`, subject `oidc`. The existing instrumentation specs subscribe to
those exact names and stay green, which is the name-unchanged proof.

**The cardinality/PII guard now reads the redaction config (WS1.5).** Guards in
`spec/providers/oidc_instrumentation_spec.rb` and
`spec/requests/sessions_instrumentation_spec.rb` drive the provider + a full
login and assert `payload.keys & Partitia::Support::RedactionConfig.sensitive_fields
== []` — forbidden set **read from Plan 006's config, not hard-coded**. Added:
verify-outcome-per-failure-path, `endpoint`/no-`url` on http, `exchange_code`
outcome, and `not have_key(:subject)` on verify.

### How to run

`cd gems/cognito && bundle exec rspec` → 51 examples, 0 failures;
`bundle exec rubocop` → clean on changed files.

### Dashboards (WS2) & how to point the stack at them

CNFS Grafana dashboards live in
`~/spikes/chorus/storage/telemetry/dashboards/cnfs/`
(`cnfs-auth-overview.json`, `cnfs-operation-latency.json`; stable uids). They
query the **Tempo** datasource (uid `tempo`) with TraceQL-metrics over
`partitia_cognito.*` / `partitia_iam.*` span names + the WS1 dimensions (`outcome`,
`endpoint`, `status`, `policy`, `rotated`). Point the stack at them by setting
**`DASHBOARDS_DIR`** in `services/telemetry/.env` (gitignored; `.env.example`
documents it) to that store, then `podman compose up -d`.

**Verified (WS3, complete).** The `single` boot failure was a leaked `RUBYLIB`,
not a missing dep — `unset RUBYLIB && bin/rails …` boots. Drove the registered
provider (`Partitia::Cognito::Providers::Authentik`) against a **live Authentik** at
`:9000` (bad-token verify → `outcome=malformed`; bogus exchange_code →
`outcome=failed` + discovery/token http spans), `force_flush`ed, inspected
Tempo. Confirmed on real spans: `verify.outcome`=malformed,
`http.endpoint`=discovery/token, and **no `subject` attribute anywhere**
(TraceQL search for a subject-bearing cnfs span → 0). Both dashboards provision
into the "cnfs" folder and **every panel query returns real series against live
data**.

**Two findings the live run forced (dashboards corrected accordingly):**
1. **Attribute keys are namespaced by the full event name.** The `partitia-telemetry`
   bridge sets `span."#{event_name}.#{key}"` (intentional + tested), so a query
   references `span."partitia_cognito.authentik.verify.outcome"`, not `span.outcome`.
2. **Cognito span names carry the provider subject.** `Authentik < Oidc` (empty
   subclass) ⇒ real spans are `partitia_cognito.authentik.*`, not `…oidc.*` — the
   name the specs assert (they test `Oidc` directly). The plan assumed `oidc` +
   bare attribute keys; the dashboards now use the verified `authentik` names and
   fully-qualified keys. Both are bridge/provider behavior outside WS1 scope —
   flagged for architecture (they couple every dashboard query to the exact span
   name and to the active provider). Also noted separately: `single`'s
   `config/partitia_cognito.yml` still holds a **plaintext client_secret** (a
   config/secrets issue, not telemetry — belongs to the Plan 006 rotation TODO
   above, but re-confirmed present).

---

## D3 — Engine contract (2026-10-22)

- Registered: `Partitia::Support.plugins << self` in the engine (§3, Q6).
- `partitia.services = "authentik"` in the gemspec (§9).
- Install generator: initializer and `config/partitia_cognito.yml` guarded (skip if
  present); yml points development at pcm's Authentik
  (`http://localhost:9000/application/o/<app-slug>/`, client_id `<app-slug>`), test
  has stubs, production reads ENV/credentials, no `client_secret` anywhere; `:code`,
  `:state` injected into `filter_parameter_logging.rb` (created if missing); prints
  the entry points and what is left. Second run: all `skip`, no prompt.
- Private Authentik harness removed (`spec/dummy/docker/authentik`, `bin/authentik`,
  the Procfile line): pcm's `stack/authentik` (`pcm up authentik`) replaces it. The
  live discovery spec is no longer tag-excluded; it skips unless `AUTHENTIK_ISSUER`
  is set and answers.
- Specs: 51 → 63 examples (+10 generator, +2 engine), 1 pending (the live spec).
