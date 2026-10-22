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

## D0 — Tooling: the `partitia` CLI

- [x] `new`, `list`, `server` (0.0.0.0 through `bin/dev`), `log`, `engine new`, `template`,
      `path`/`cd`, `config`; bats suite
- [ ] `engine check` — an engine against the contract (D2)
- [ ] `services` — the pcm services the app's engines declare, up/down
- [ ] `smoke` — the D6 acceptance as a command

## D1 — Ground truth

- [ ] Spec baseline: each gem bundled and its suite run, before anything changes
- [ ] Rename to `partitia-*` / `Partitia::*`: gemspecs, modules, files, generators, table
      prefixes, config names, instrumentation events
- [ ] Declare sibling runtime dependencies in the gemspecs (today they come only from Gemfile
      `path:` entries)
- [ ] gem-local: add this repo, `gem-local build`; every gem loads from anywhere
- [ ] Specs green against the baseline
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

## D4 — pcm wiring

- [ ] telemetry: OTLP to `stack/telemetry` (`localhost:4318`)
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
