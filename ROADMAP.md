# Roadmap

Partitia is the set of Rails engines every CNFS app builds on: support, dev, telemetry, tenanted,
iam, cognito, ui. Appwork (shared functionality only some apps need) comes later.

**Near-term destination:** `pt new single`, choose engines through the recipe, `pt server` on
0.0.0.0, and the app works against the pcm services: login through Authentik, traces in Grafana,
errors in GlitchTip. Then the same for `multi` (multi-tenant).

## Decisions

- **Naming:** gems are `partitia-<name>`, modules `Partitia::<Name>` (the `mission_control-jobs`
  pattern). `Partitia::Iam`, never `IAM`: an acronym inflection in an engine changes the host
  app's inflections. No Partitia gem defines a top-level constant (tenanted's `Tenant` and
  `GlobalRecord` move under `Partitia::Tenanted`).
- **Apps are generated, not maintained.** `apps/` holds recipes (`single.yml`, `multi.yml`); the
  apps themselves are throwaway output of `pt new`. A hand edit to a generated app means a
  template or generator is missing something.
- **UI:** apps use Phlex and RubyUI; no ERB. Engine views are Phlex classes using RubyUI
  components; each engine declares the components it needs and its installer adds them to the
  app (RubyUI copies source into the app). The `ui` engine is shelved until engines duplicate
  view code.
- **Docs:** `doc/` (ADRs, plans 001–012) and the Obsidian notes are a baseline to mine, not to
  bring up to date. New docs start from the code. ADRs 0002–0004 match the code and carry over.
- **Tooling:** `partitia` (`pt`), an anfs tool in the cnfs source's `rails` package, is how
  engines and apps are made and run. Generic Rails shell helpers are stack's `rails` package.
- **URNs:** the partition is the app's (`Partitia::Support::UrnConfig`,
  `PARTITIA_URN_PARTITION`, default `partitia`), and `find_by_urn` only resolves this app's,
  service's and account's URNs (ADR 0007). Event and span names stay `partitia_*` in every app;
  apps differ by OpenTelemetry `service.name`.
- **Skills come after the thing they describe is stable**, one per task, not per engine:
  `partitia-engines` (building an engine) after D2–D3, `partitia-apps` (building an app: the
  application builder, onboarding) after D6. Engine-specific knowledge lives in the engine's
  README and install generator. Each destination closes with a short "what an agent needs to
  know" note below, so the skills start from what was learned.

## D0 — Tooling: the `partitia` CLI

- [x] `new`, `list`, `server` (0.0.0.0 through `bin/dev`), `log`, `engine new`, `template`,
      `path`/`cd`, `config`; bats suite
- [ ] `engine check` — an engine against the contract (D2)
- [ ] `services` — the pcm services the app's engines declare, up/down
- [ ] `smoke` — the D6 acceptance as a command

## D1 — Ground truth

- [x] Spec baseline: each gem bundled and its suite run, before anything changes
- [x] Rename to `partitia-*` / `Partitia::*`: gemspecs, modules, files, generators, table
      prefixes, config names, instrumentation events
- [x] Declare sibling runtime dependencies in the gemspecs (optional integrations detected
      with `defined?` stay undeclared)
- [x] gem-local: add this repo, `gem-local build`; every gem loads from anywhere
- [x] Specs green against the baseline
- [x] URN partition is the app's, default `partitia`; strict `find_by_urn` (ADR 0007)
- [ ] CI: an RSpec job alongside lint, on the same per-gem matrix (CI runs RuboCop only today)

## D2 — The engine contract

- [ ] `ARCHITECTURE.md`: the layers (base: support, dev, telemetry; identity: tenanted, iam,
      cognito; presentation: ui), the dependency rules, and what every engine provides: an
      idempotent `partitia:<name>:install` generator, config through `Partitia::Support::Config`
      with pcm defaults, registration with the plugin registry, single- and multi-tenant
      operation, no hard dependency on an optional sibling

## D3 — Each engine meets the contract on its own

- [ ] In order: support, dev, telemetry, tenanted, iam, cognito; each installed into a fresh app,
      not only its dummy
- [ ] dev gets specs; iam's install generator is wired into the templates
- [ ] Known from the rename: tenanted's dummy test DB needs a manual `db:prepare` before its
      specs pass; `partitia:tenanted:views` has no `source_root`; ui's `eager_load!` fails on
      the RubyUI Button

## D4 — pcm wiring

- [ ] telemetry: OTLP to `stack/telemetry` (`localhost:4318`); the app sets `service.name`
- [ ] Grafana dashboards in this repo, provisioned through `GRAFANA_DASHBOARDS_DIR`, querying the
      `partitia_*` span names (the old `cnfs-*` dashboards are gone and queried `cnfs_*`)
- [ ] errors: `sentry-rails` to `stack/glitchtip`
- [ ] cognito: `stack/authentik`, with a blueprint that registers the OIDC client (no manual
      wizard)

## D5 — Template shakedown

- [ ] Engines by gem name through gem-local, not `~/spikes/chorus` paths; no `binding.pry`
- [ ] The recipe selects engines (`partitia.yml` / `<app>.yml`)
- [ ] Phlex + RubyUI layout and app shell; a Tailwind `@source` line for each engine

## D6 — The demo

- [ ] `single`: `pt new single` → `pt server` → Authentik login, a trace in Grafana, an error in
      GlitchTip; scripted as `pt smoke`
- [ ] `multi`: tenant from subdomain (`*.localhost`), and Authentik redirect URIs across tenant
      subdomains (callback on the apex, or a regex redirect)

## Outside this repo

- [ ] appwork: its gems still use the old names (`CnfsSupport`, `cnfs_*` gems, `Iam::`, `iam_`
      tables), about 45 files across chatter, chorus, gtd, micro_manager and okf
- [ ] `~/.config/rails/templates/cnfs.rb`: old gem and generator names (D5 rewrites it)
