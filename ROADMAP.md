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
- [x] `engine check [gem...]` — the contract's static checks per gem (naming, Ruby, lockfile
      platforms, CI matrix, test schema, no `force: true`, registration, install generator, ERB
      views as a warning until D5); failures and warnings only unless `--all`; exit 1 on failure
- [ ] `services` — the pcm services the app's engines declare, up/down
- [ ] `smoke` — the D6 acceptance as a command. Cheap first: `/up` 200, `/auth/login` 302 to
      Authentik, a forced error lands in GlitchTip, a trace in Tempo (curl + `pcm exec`). A real
      headless login as the bootstrap admin is later
- [x] `ci [gem...]` — what CI runs (Ruby and gem matrix from `.github/workflows/ci.yml`), in
      pcm's `ruby-ci` job container via `pcm run`: fresh clone, frozen bundle, rspec, rubocop;
      a GEM STATUS SPECS LINT table, exit 1 on failure. Gems are cached per Ruby, so a warm run
      is about 30 s a gem

## D1 — Ground truth

- [x] Spec baseline: each gem bundled and its suite run, before anything changes
- [x] Rename to `partitia-*` / `Partitia::*`: gemspecs, modules, files, generators, table
      prefixes, config names, instrumentation events
- [x] Declare sibling runtime dependencies in the gemspecs (optional integrations detected
      with `defined?` stay undeclared)
- [x] gem-local: add this repo, `gem-local build`; every gem loads from anywhere
- [x] Specs green against the baseline
- [x] URN partition is the app's, default `partitia`; strict `find_by_urn` (ADR 0007)
- [x] CI: an RSpec job alongside lint, on the same per-gem matrix; both green on Ruby 4.0.7
      (checked in a `ruby:4.0.7` Linux container from a fresh clone, lockfiles frozen)

**What an agent needs to know (D1):**
- Each gem bundles and runs alone: `cd <gem> && bundle exec rspec`; siblings come from Gemfile
  `path: "../<dir>"` entries, and from anywhere else through gem-local.
- A fresh checkout has no test databases. Rails dummies load their schema through
  `ActiveRecord::Migration.maintain_test_schema!` in `spec/rails_helper.rb`; a new engine needs
  the same line.
- Lockfiles carry `arm64-darwin`, `x86_64-linux-gnu` and `aarch64-linux-gnu`; a new gem's
  lockfile needs `bundle lock --add-platform x86_64-linux-gnu aarch64-linux-gnu` or CI cannot
  install its native gems.
- A gemspec without `required_ruby_version` makes RuboCop parse it as Ruby 2.7 and report
  `Lint/Syntax` on modern code.
- CI's Ruby is `RUBY_VERSION` at the top of `.github/workflows/ci.yml`; keep it the Ruby the specs
  were run on.

## D2 — The engine contract

- [x] Drafted from the code: `ARCHITECTURE.md` (layers, contract §1–§10, each engine's gaps,
      today's wiring, questions Q1–Q7); repo `AGENTS.md`; support's `CLAUDE.md` is its `AGENTS.md`
- [x] Reviewed together; Q1–Q7 answered (with the evidence from the earlier apps); Agreed

## D3 — Each engine meets the contract on its own

- [x] In order: support, dev, telemetry, tenanted, iam, cognito; each installed into a fresh app,
      not only its dummy (single- and multi-tenant `rails new` apps: second runs change nothing,
      databases migrate, served on 0.0.0.0)
- [x] dev gets specs (72)
- [ ] iam's install generator is wired into the templates (D5)
- [x] Known from the rename: `partitia:tenanted:views` `source_root`; ui's `eager_load!`; tenanted's
      test DB
- [x] The gaps table in `ARCHITECTURE.md`, engine by engine; what is left there is small or
      belongs to D5 (ERB views, ui's installer)
- [x] Small follow-ups from that table: cognito's unreachable IdP is a 503 (was a 500); dev
      loads `pry-byebug` only with the console; iam's README lists its integrations
- [ ] tenanted's `trace` setting (may belong in telemetry's config, Q2)
- [x] tenanted: migration status for tenant databases: `partitia:tenanted:migrate:status`

**What an agent needs to know (D3):**
- `pt engine check` is the contract's static check; run it after touching an engine.
- Prove an engine in a fresh `rails new` app, not only its dummy: install twice (the second run
  must leave `git status` clean), `db:prepare`, `pt server`, real requests. Both bugs D3 found
  (support's installer on a tenanted `database.yml`; `*.localhost` never resolving a tenant)
  passed every spec and showed up only there.
- Install order: `partitia:tenanted:install` before anything that edits `database.yml`.
- Parallel agents share the session's scratchpad: give each its own uniquely named directory;
  one agent's `rm -rf fresh` deleted another's app.

## D4 — pcm wiring

- [ ] telemetry: OTLP to `stack/telemetry` (`localhost:4318`); the app sets `service.name`
- [ ] Grafana dashboards in this repo, provisioned through `GRAFANA_DASHBOARDS_DIR`, querying the
      `partitia_*` span names (the old `cnfs-*` dashboards are gone and queried `cnfs_*`)
- [ ] errors: `sentry-rails` to `stack/glitchtip`
- [ ] cognito: `stack/authentik`, with a blueprint that registers the OIDC client (no manual
      wizard)
- [ ] `pt services`: provisions each installed engine's services through pcm's public commands
      only (`pcm provision`/`deprovision`, pcm 0.3.0); never commits a secret.
      - Non-secrets (issuer, client_id) are deterministic for pcm and already written by the
        installers; `pt services` checks they agree.
      - Secrets (the DSN; later CLIENT_SECRET) go to a store, `PARTITIA_SECRETS_STORE`:
        `local` (default): `config/partitia_<engine>.local.yml`, `/config/*.local.yml` gitignored;
        `fnox`: piped to `fnox set` in the app's `fnox.toml` with the space's provider (1Password
        through its service-account token), so fnox exports `PARTITIA_<ENGINE>_*`. Both reach
        the engines through anyway_config with no engine code; `pt server` runs under
        `fnox exec` when a `fnox.toml` is present
      - First run points `GRAFANA_DASHBOARDS_DIR` (`~/.config/pcm/env/telemetry.env`) at
        `telemetry/dashboards/` in this repo

How it is built:

- The containers change in stack (pcm-containers skill), modelled on `postgres/provision`:
  authentik gets bootstrap admin/token settings, a blueprints mount, and `provision`/
  `deprovision` hooks that apply an idempotent per-app blueprint and print `ISSUER`, `CLIENT_ID`;
  glitchtip gets hooks that create the org and project and print `DSN`
- Hooks run only through pcm. Before `pcm provision` lands, test them through a scratch local
  pcm definition that lists the service in `x-pcm.depends_on`, never by running the script
- OIDC client type is a setting: `client_type=public|confidential` in the authentik hook and
  in cognito's config. Only `public` (PKCE, no secret) is implemented; `confidential` is
  rejected with "not yet supported", leaving room for the secret to flow through `pt services`
  into credentials later

Later (longer term):

- [ ] Confidential OIDC clients: the hook generates and prints `CLIENT_SECRET`, `pt services`
      stores it in the app's credentials, cognito sends it at the token endpoint

## D5 — Template shakedown

- [ ] Engines by gem name through gem-local, not `~/spikes/chorus` paths; no `binding.pry`
- [ ] The recipe selects engines (`partitia.yml` / `<app>.yml`)
- [ ] Phlex + RubyUI layout and app shell; a Tailwind `@source` line for each engine. Source:
      the earlier `fudge` app (`apps/fudge`): its `phlex.rb` and `ruby_ui.rb` initializers,
      `Components::Base`/`Views::Base`, shadcn design tokens, the RubyUI component flow
- [ ] Later, for support and ui: fudge's `TableDefinition` (declarative columns, param allowlist,
      search and facets) and `Components::DataTable` (RubyUI DataTable, pagy), both marked there
      for "eventual home" in the gems
- [ ] When D5 has taken what it needs from `apps/` (single, multi, factory, fudge: the apps built on
      the earlier gems, broken since the move), the person removes it

## D6 — The demo

- [ ] `single`: `pt new single` → `pt server` → Authentik login, a trace in Grafana, an error in
      GlitchTip; scripted as `pt smoke`
- [ ] `multi`: tenant from subdomain (`*.localhost`); Authentik accepts every tenant through one
      regex redirect (`redirect_regex=` on the authentik hook, e.g.
      `http://[a-z0-9-]+\.localhost:3000/auth/callback`), each tenant keeping its own session.
      Production custom domains: later

## Outside this repo

- [ ] appwork: its gems still use the old names (`CnfsSupport`, `cnfs_*` gems, `Iam::`, `iam_`
      tables), about 45 files across chatter, chorus, gtd, micro_manager and okf
- [ ] `~/.config/rails/templates/cnfs.rb`: old gem and generator names (D5 rewrites it)
