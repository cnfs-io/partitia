# Roadmap

Partitia is the set of Rails engines every CNFS app builds on: support, dev, telemetry, tenanted,
iam, cognito, ui. Appwork (shared functionality only some apps need) comes later.

**Near-term destination:** `cnfs new single`, choose engines through the recipe, `cnfs server` on
0.0.0.0, and the app works against the pcm services: login through Authentik, traces in Grafana,
errors in GlitchTip. Then the same for `multi` (multi-tenant).

## Decisions

- **Naming:** gems are `partitia-<name>`, modules `Partitia::<Name>` (the `mission_control-jobs`
  pattern). `Partitia::Iam`, never `IAM`: an acronym inflection in an engine changes the host
  app's inflections. No Partitia gem defines a top-level constant (tenanted's `Tenant` and
  `GlobalRecord` move under `Partitia::Tenanted`).
- **Apps are generated, not maintained.** `apps/` holds recipes (`single.yml`, `multi.yml`); the
  apps themselves are throwaway output of `cnfs new`. A hand edit to a generated app means a
  template or generator is missing something.
- **UI:** apps use Phlex and RubyUI; no ERB. Engine views are Phlex classes using RubyUI
  components; each engine declares the components it needs and its installer adds them to the
  app (RubyUI copies source into the app). The `ui` engine is shelved until engines duplicate
  view code.
- **Docs:** `doc/` (ADRs, plans 001–012) and the Obsidian notes are a baseline to mine, not to
  bring up to date. New docs start from the code. ADRs 0002–0004 match the code and carry over.
- **Tooling:** `cnfs`, an anfs tool in the cnfs source's `rails` package, is how engines and
  apps are made and run. Generic Rails shell helpers are stack's `rails` package.
- **URNs:** the partition is the app's (`Partitia::Support::UrnConfig`,
  `PARTITIA_URN_PARTITION`, default `partitia`), and `find_by_urn` only resolves this app's,
  service's and account's URNs (ADR 0007). Event and span names stay `partitia_*` in every app;
  apps differ by OpenTelemetry `service.name`.
- **Skills come after the thing they describe is stable**, one per task, not per engine:
  `partitia-engines` (building an engine) after D2–D3, `partitia-apps` (building an app: the
  application builder, onboarding) after D6. Engine-specific knowledge lives in the engine's
  README and install generator. Each destination closes with a short "what an agent needs to
  know" note below, so the skills start from what was learned.

## D0 — Tooling: the `cnfs` CLI

D0 built `cnfs` (formerly `partitia`, alias `pt`).

- [x] `new`, `list`, `server` (0.0.0.0 through `bin/dev`), `log`, `engine new`, `template`,
      `path`/`cd`, `config`; bats suite
- [x] `engine check [gem...]` — the contract's static checks per gem (naming, Ruby, lockfile
      platforms, CI matrix, test schema, no `force: true`, registration, install generator, ERB
      views as a warning until D9); failures and warnings only unless `--all`; exit 1 on failure
- [x] `services` — the pcm services the app's engines declare, up/down (`--down` also takes the
      DSN out of the secrets store)
- [x] `smoke [app]` — the D6 acceptance as a command. Cheap first: `/up` 200, `/auth/login` 302 to
      Authentik, a forced error lands in GlitchTip, a trace in Tempo (curl + `pcm exec`); CHECK
      STATUS DETAIL, exit 1 on failure, about 35 s. `--login` (D6) adds a real headless sign-in
      as Authentik's bootstrap admin (`--host acme.localhost` on a tenant)
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
- [x] iam's install generator is wired into the templates (D5)
- [x] Known from the rename: `partitia:tenanted:views` `source_root`; ui's `eager_load!`; tenanted's
      test DB
- [x] The gaps table in `ARCHITECTURE.md`, engine by engine; what is left there is small or
      belongs to D9 (ERB views, ui's installer)
- [x] Small follow-ups from that table: cognito's unreachable IdP is a 503 (was a 500); dev
      loads `pry-byebug` only with the console; iam's README lists its integrations
- [x] tenanted's `trace` setting: removed in D6; telemetry's `rack_tracing` is the one control
- [x] tenanted: migration status for tenant databases: `partitia:tenanted:migrate:status`

**What an agent needs to know (D3):**
- `cnfs engine check` is the contract's static check; run it after touching an engine.
- Prove an engine in a fresh `rails new` app, not only its dummy: install twice (the second run
  must leave `git status` clean), `db:prepare`, `cnfs server`, real requests. Both bugs D3 found
  (support's installer on a tenanted `database.yml`; `*.localhost` never resolving a tenant)
  passed every spec and showed up only there.
- Install order: `partitia:tenanted:install` before anything that edits `database.yml`.
- Parallel agents share the session's scratchpad: give each its own uniquely named directory;
  one agent's `rm -rf fresh` deleted another's app.

## D4 — pcm wiring

- [x] telemetry: OTLP to `stack/telemetry` (`localhost:4318`); the app sets `service.name`
- [x] Grafana dashboards in this repo, provisioned through `GRAFANA_DASHBOARDS_DIR`, querying the
      `partitia_*` span names (the old `cnfs-*` dashboards are gone and queried `cnfs_*`):
      `telemetry/dashboards/`, Partitia / Overview and Partitia / Identity
- [x] request spans: OTel's Rack, ActionPack and ActionView instrumentation, wired by
      telemetry's installer behind `rack_tracing` (default on,
      `PARTITIA_TELEMETRY_RACK_TRACING=false`); the `partitia_*` spans are their children
- [x] errors: `sentry-rails` to `stack/glitchtip`, including `Rails.error.report` (the generated
      `sentry.rb` sets `register_error_subscriber`, off in sentry-rails)
- [x] cognito: `stack/authentik`, with a blueprint that registers the OIDC client (no manual
      wizard). `cnfs services` provisions it and `/auth/login` redirects to it with the client
      (`cnfs smoke`); a real sign-in through it is proven in D6 (`cnfs smoke --login`)
- [x] `cnfs services`: provisions each installed engine's services through pcm's public commands
      only (`pcm provision`/`deprovision`, pcm 0.3.0); never commits a secret.
      - Non-secrets (issuer, client_id) are deterministic for pcm and already written by the
        installers; `cnfs services` checks they agree.
      - Secrets (the DSN; later CLIENT_SECRET) go to a store, `CNFS_SECRETS_STORE`:
        `local` (default): `config/partitia_<engine>.local.yml`, `/config/*.local.yml` gitignored;
        `fnox`: piped to `fnox set` in the app's `fnox.toml` with the space's provider (1Password
        through its service-account token), so fnox exports `PARTITIA_<ENGINE>_*`. Both reach
        the engines through anyway_config with no engine code; `cnfs server` runs under
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
  rejected with "not yet supported", leaving room for the secret to flow through `cnfs services`
  into credentials later

**What an agent needs to know (D4):**
- The loop is `pcm up telemetry` → `cnfs services` → `cnfs server` → `cnfs smoke`. Grafana is
  <http://localhost:8080> (anonymous); Tempo publishes no port: query it through Grafana's
  datasource proxy (`/api/datasources/proxy/uid/tempo/api/search`) or
  `pcm exec -s grafana telemetry -- wget -qO- http://tempo:3200/...`.
- A trace shows in Tempo about 30 s after the request (5 s batch export, then the live-store);
  an empty search right after a request means wait, not broken. `smoke` polls for 120 s.
- Every request is a trace rooted at OTel's server span (`GET /up`, `GET /auth/login`), with
  the `partitia_*` spans as children (`rack_tracing`, default on). With
  `PARTITIA_TELEMETRY_RACK_TRACING=false` only `partitia_*` events become spans and `/up` has
  no trace. `/auth/login` gives `partitia_cognito.sessions_controller.login_start` and the IdP
  discovery call either way; `smoke` takes the newest trace for the service.
- Span attributes are `<event name>.<payload key>`
  (`span.partitia_cognito.sessions_controller.callback.outcome`); the dashboards group by them.
  Tempo 3 serves TraceQL metrics (`| rate()`, `quantile_over_time`) from its live-store with no
  Prometheus or metrics-generator: dashboards cover recent data only (1 h retention).
- Grafana runs TraceQL *search* panels in the browser; `/api/ds/query` answers them with "backend
  TraceQL search queries are not supported". Check metrics panels through `/api/ds/query`,
  search panels through the proxy.
- The forced error is `Rails.error.report` through `bin/rails runner` (one GlitchTip issue,
  "cnfs smoke: a forced error", one event a run). An app made before the `sentry.rb` change lacks
  `register_error_subscriber` and reports nothing that way: add the line, or delete `sentry.rb`
  and re-run `partitia:telemetry:install`.
- GlitchTip's events for an app: `pcm exec -s web glitchtip -- ./manage.py shell -c ...` with
  `IssueEvent.objects.filter(issue__project__organization__slug="partitia",
  issue__project__slug=<slug>)`.
- Container logs: `pcm logs <service> [-s NAME] [-f] [--tail N] [--since T]` (pcm 0.4.0).

Later (longer term):

- [ ] Confidential OIDC clients: the hook generates and prints `CLIENT_SECRET`, `cnfs services`
      stores it in the app's credentials, cognito sends it at the token endpoint

## D5 — Recipes and template

`cnfs new single|multi` produces a wired app with no manual steps. D6 depends on it; the UI does
not (that is D9).

- [x] Engines by gem name through gem-local, not `~/spikes/chorus` paths; no `binding.pry`
- [x] The recipe selects engines: `single` and `multi` recipes (`partitia.yml` / `<app>.yml`)
- [x] `~/.config/rails/templates/cnfs.rb` rewritten as `partitia.rb`: the engines' installers in
      the D3 order (tenanted before anything that edits `database.yml`), then `db:prepare`
- [x] Proven like D3: a fresh `cnfs new single` and `cnfs new multi`, installers re-run with no
      changes, `cnfs services`, `cnfs server`, `cnfs smoke`

**What an agent needs to know (D5):**
- `cnfs new <recipe> <name> [rails new options]`; `cnfs new <name>` alone is a plain `rails new` (plus
  `<name>.yml` beside it, if any). A recipe is `<recipe>.yml` in `CNFS_APPS_HOME`, else the
  shipped `~/.config/rails/recipes/{single,multi}.yml` (cnfs `rails` package). `cnfs` hands it to the
  templates as `CNFS_RECIPE`; `lib.rb` merges it over `partitia.yml`, and `<name>.yml` over it.
- A recipe is the templates' answers: `templates.partitia.engines` (and `tenants` for the demo
  tenants), every `dev` gem answered, and `ui: false` (a template set to `false` is not applied).
  Any template gem left without an `install:` answer makes `rails new` stop and ask.
- `templates/partitia.rb` adds `partitia-<engine>` lines to the Gemfile with
  `path: "#{partitia_gems}/partitia-<engine>"`, `partitia_gems` being gem-local's home
  (`RUBY_LOCAL_GEMS_HOME`) read when bundler runs; `Gemfile.lock` still records the absolute path.
  It fails early when an engine is not linked (`gem-local build`). After bundling: the installers
  in D3's order, `db:prepare`, and with tenanted a guarded block in `db/seeds.rb` (platform
  database, then `Tenant` per demo subdomain) and `db:seed`.
- The app records its recipe in `./partitia.yml` (`recipe:` and the engines); `cnfs list`'s RECIPE
  reads it, and `cnfs template apply partitia` re-runs everything from it. That re-run leaving
  `git status` clean is the idempotency check.
- The template adds `/config/*.local.yml` to `.gitignore`, so `cnfs services` (local store) leaves a
  fresh app clean.
- Tenant resolution runs in `ApplicationController`: `/` on a fresh app is Rails' welcome page and
  resolves nothing. Check it with `/tenants`: `acme.localhost` 403 (the console guard, after the
  tenant resolved), an unknown subdomain 302 to `/tenant-unknown`.
- `cnfs engine check` with no gems fails on `ui` (no installer: D9); check the recipe's engines by
  name.

## D6 — The demo

- [x] `single`: `cnfs new single` → `cnfs services` → `cnfs server` → Authentik sign-in, a trace in
      Grafana, an error in GlitchTip; scripted as `cnfs smoke --login` (curl, headless, as akadmin)
- [x] `multi`: tenant from subdomain (`*.localhost`); Authentik accepts every tenant through one
      regex redirect (`redirect_regex=` on the authentik hook, stack authentik 0.3.0;
      `cnfs services` adds `http://[a-z0-9-]+\.localhost:<port>/auth/callback` beside the strict
      apex one), each tenant keeping its own session (host-only cookie) and principals (its own
      database). Production custom domains: later
- [x] First sign-in with the fail-closed default: root claims itself with its bootstrap link token
      (`bin/rails partitia:iam:bootstrap [TENANT=<subdomain>]`); `/me` is the check page
- [ ] **The person signs in via browser** (the checklist below)
- [x] Sign-in on a multi-tenant app's apex or an unknown subdomain (was: to Authentik, then a 500,
      `NoTenantError`). A sign-in needs the database the Rack layer selected; tenanted adds a
      cognito `before_sign_in` hook: an unknown subdomain redirects to `/tenant-unknown`, the
      apex answers 404 ("sign in at your workspace's address"), both before the IdP. The apex
      is not a sign-in (ADR 0003 §8); the platform's sign-in stays a host entry point that pins
      the reserved database (the dummy's `/platform/login`); its root's token is
      `partitia:iam:bootstrap TENANT=platform`
- [x] One control for request tracing: tenanted's `config.partitia_tenanted.trace` and its request
      span are gone; with telemetry's `rack_tracing` the server span carries `tenant.subdomain`
      and `tenant.handle` (set at the Rack layer); Overview's tenant panels query it

**Browser check (the person).** Authentik's admin is `akadmin`; its password is
`AUTHENTIK_BOOTSTRAP_PASSWORD` in `~/.config/pcm/containers/authentik/local.env` if you set it
there, else that variable's default in the authentik definition's `.env.schema`
(`pcm path authentik`). Authentik reads it on its first start only: if you changed the password
in Authentik since, use yours.

1. [ ] `pcm up telemetry`; `cnfs new single demo1 && cnfs services && cnfs server` (port 3000; another
       port: `CNFS_PORT=<port>` for both `cnfs services` and `cnfs server`)
2. [ ] In the app: `bin/rails partitia:iam:bootstrap` prints `ROOT=unclaimed` and
       `LINK_TOKEN=<token>`
3. [ ] Open `http://localhost:3000/auth/login?link_token=<token>`: Authentik's sign-in page;
       sign in as `akadmin`
4. [ ] You land on <http://localhost:3000/me>: "Signed in", the root principal (`owner@demo1.test`,
       `urn:partitia:iam::<account>:user/1 (root)`), database `storage/development.sqlite3`
5. [ ] Sign out (the button), then <http://localhost:3000/me> again: it goes to Authentik and back
       with no token (Authentik remembers you; root is claimed: the task now prints
       `ROOT=claimed`)
6. [ ] Multi: `cnfs new multi demo2 && cnfs services && cnfs server`, then
       `bin/rails partitia:iam:bootstrap TENANT=acme` and
       `http://acme.localhost:3000/auth/login?link_token=<token>`: `/me` on `acme.localhost`,
       root `owner@acme.test`, database `storage/development/<acme's handle>.sqlite3`
7. [ ] Still in demo2: <http://localhost:3000/me> on the apex is not signed in (sessions are per
       host): it sends you to `/auth/login`, a 404 "No workspace here: sign in at your
       workspace's address", with no trip to Authentik; <http://bogus.localhost:3000/me> and
       <http://bogus.localhost:3000/auth/login> go to `/tenant-unknown` ("We couldn't find that
       workspace")

**What an agent needs to know (D6):**
- First sign-in: cognito fails closed (`:invite_only`; its installer no longer sets `:jit`). Each
  database has one root principal; `bin/rails partitia:iam:bootstrap` (iam,
  `Partitia::Iam::Bootstrap`) seeds it where nothing did (a single-tenant app) and, while root
  has no identity link, issues a new single-use link token (stdout `ROOT=`, `LINK_TOKEN=`). The
  first sign-in with `/auth/login?link_token=` binds that IdP identity to root. Each run while
  unclaimed invalidates the previous token. Multi: `TENANT=<subdomain>` (or `platform`); tenants
  are seeded on creation.
- Tenant sign-in needs no app wiring: tenanted selects the database at the Rack layer
  (`Partitia::Tenanted.request_handle` given to activerecord-tenanted's middleware), so cognito's
  mounted callback runs in the tenant's database. The dummy's `identity.rb` only adds the
  platform flag on top.
- Authentik's ID token `iss` ends in `/`; cognito compared it with the slash trimmed and refused
  every real sign-in (its specs used an issuer without one). Now `iss` must equal the configured
  issuer exactly. The live discovery spec (`spec/integration`) passes against pcm's Authentik.
- Headless sign-in: `/auth/login` → Authentik's authorize → `/if/flow/<slug>/?<query>`; drive it
  through `GET/POST /api/v3/flows/executor/<slug>/?query=<that query, encoded>` with one cookie
  jar: `ak-stage-identification` (`uid_field`), `ak-stage-password` (`password`, on stdin), then
  `xak-flow-redirect` back to authorize, which (implicit consent) redirects to the app's
  callback. No CSRF header is needed. `cnfs smoke --login` does exactly this.
- The bootstrap admin's password is in the running container's environment:
  `pcm exec -s server authentik -- printenv AUTHENTIK_BOOTSTRAP_PASSWORD` (into a variable, never
  echoed).
- Authentik `fullmatch`es regex redirect URIs; the hook still stores `^(?:…)$`. A `redirect_uri`
  that matches nothing (another port or host) is a 400 "Redirect URI Error" at authorize.
- `/me` (from the template, app-owned, tiny ERB until D9) is where cognito lands after sign-in
  (`after_sign_in_path`); it shows the principal and the database it was read from.
- `curl` 8.x resolves `*.localhost` to loopback by itself; no `--resolve` needed.
- Don't edit the `cnfs` script while a `cnfs` command runs: bash reads the script as it goes
  (a `cnfs new` died after `rails new` finished when the file changed under it).
- Where tenanted selected no database there is no sign-in: cognito's `before_sign_in` hooks
  (tenanted adds one) run before `/auth/login` and `/auth/callback`. Unknown subdomain:
  `/tenant-unknown`; apex: 404. `cnfs smoke` in a multi-tenant app expects that 404 on the apex
  and checks a tenant's redirect with `--host`. The apex stays untenanted on purpose: pinning
  it to the platform database would make the console's `POST /tenants` provision inside
  activerecord-tenanted's shard-swap lock, and the reserved database would answer app queries
  unguarded (ADR 0003 §2).
- Request tracing is one switch, `rack_tracing`. tenanted sets `tenant.subdomain`/`tenant.handle`
  on the current span from `Partitia::Tenanted.request_handle`, which runs inside OTel's Rack
  server span (support's `Instrumentable.set_span_context`: no telemetry dependency). Inside a
  `partitia_*` notification block the current span is that event's span, not the server span.
- Code reloading in development: tenanted re-applies `subtenant_of` to each engine's
  `ApplicationRecord` in `to_prepare`. In `after_initialize` a reload left iam's models on the
  global database and every sign-in callback was a 500 (`Could not find table
  'partitia_iam_identity_links'`) until the server restarted.

Found while drawing DIAGRAMS.md (2026-10-22), small, after the pause:

- [ ] ARCHITECTURE §4: the real anyway_config order includes `config/<name>.local.yml` (dev,
      flat; `cnfs services` relies on it) and `config/credentials/local.yml.enc`; the ejson and
      doppler loaders would override ENV when present: decide whether `Partitia::Support::Config`
      disables them
- [ ] ARCHITECTURE §6 says the platform database holds identity only, but it gets every tenant
      migration (host tables too); only `with_platform`'s scope guard limits it. Fix the doc or
      the migrations
- [ ] tenanted's Engine body replaces support's `migrations_paths_for` at load time (a multi app
      has no `:primary` scope); works only because it runs at `Bundler.require`. Make it an
      explicit registration
- [ ] The provisioning-time bootstrap token is only in memory (`TenantSeeder.last_bootstrap_token`,
      racy), so the first sign-in always needs `partitia:iam:bootstrap`: drop it or persist it
- [ ] Stale comments: tenanted `install.rake` (a hard-coded `db/global_migrate` line), iam's engine
      (`[:primary]`; it is `[:tenant]` in a multi app)

## Pause — the person reviews

After D6: the person reviews and pushes every repo (the first CI run on the new layout), then
tests by hand. Nothing starts until they say.

## D6.5 — Apps layer: testbed, showcase, recipe builder

The third layer beside partitia (plumbing) and appwork (business engines): applications composed
from both. Two repos, under `~/spaces/cnfs/apps/` (GitHub `cnfs-io/testbed`, `cnfs-io/showcase`):

- **testbed**: persisted, regenerable apps (what `cnfs new` makes today, kept instead of thrown
  away). A recipe per app (`single`, `multi`, `kitchen-sink` with every engine, product-shaped
  ones like LGAT and RWS), the generated app committed so regenerating after a template or
  installer change shows its diff, CI per recipe (`cnfs new`, `engine check`, `cnfs services`,
  `cnfs smoke`) against partitia and appwork at the commits under test. appwork's fresh-app proof
  happens here. Its ROADMAP holds flipper and app-level concerns.
- **showcase**: polished apps that market partitia and appwork to the world. Content after D9.

- [ ] testbed repo: README, AGENTS.md, ROADMAP, `recipes/`, `single` and `multi` generated by
      `cnfs new` (made fresh, not carried over from the old `apps/`)
- [ ] showcase repo: README and ROADMAP only
- [ ] `cnfs new` finds recipes in the testbed (a recipes path setting) as well as the shipped ones
- [ ] Engine catalog: gemspec metadata beside `partitia.services`: what an engine needs, its
      tenancy (single, multi, both), what it provides, which installers it follows; `cnfs engines`
      lists the catalog across partitia and appwork through gem-local
- [ ] Resolver: a recipe names what was asked for; dependencies and install order come from the
      catalog (replaces `partitia.rb`'s hard-coded D3 order); appwork engines in recipes
- [ ] Recipe builder: an agent skill over a non-interactive `cnfs recipe new`: describe the app,
      get a recipe from the catalog with a reason per engine, confirm, `cnfs new`
- [ ] Feature flags seam: `Partitia::Support.feature?(name, actor:)`, true unless the app wires
      flipper (actors are URNs); appwork engines gate through it; flipper itself is proven in
      the testbed

## D7 — Production deploy (to scope)

anfs is building generic infrastructure tooling (EC2, a local Proxmox VM, containers, later
k3s), which cnfs will use the way it uses pcm today. partitia's side: what an app needs from it
(filed to anfs as requirements input, r-20261022-7).

Not designed yet. The choices that touch the engines: the production database (tenanted on
SQLite, or Postgres), the deploy target (Kamal, or RWS), and the secrets path (fnox and
1Password through the space, credentials).

## D8 — appwork up to the partitia names

The ~45 files across chatter, chorus, gtd, micro_manager and okf still on the old names (see
"Outside this repo"), brought onto the partitia engines and contract.

## Services — the plumbing apps still build themselves

Gaps in "common functionality for free" (2026-10-22), most important first. Scheduled after the
pause; each becomes an engine or a feature of an existing one under the contract. Where a pcm
service is needed, the container is built in stack (pcm-containers skill), and only missing pcm
capabilities go to anfs as `anfs report` feature requests.

- [ ] **S1 Authorization:** roles and permissions beyond root (iam has a sign-in gate only):
      a policy model per account/tenant, checked in controllers and views, with URNs as subjects
      and resources
- [ ] **S2 Invitations and email:** invite a user to an account or tenant (invite_only is the
      default and the bootstrap link is the only way in today); a mailer setup and a dev mail
      catcher (pcm Mailpit, `cnfs services`)
- [ ] **S3 Background jobs:** ActiveJob/Solid Queue with the tenant carried into the job (runs
      in the tenant's database) and the trace linked to the request that enqueued it
- [ ] **S4 Audit log:** who did what to which URN, from the `partitia_*` event stream; per
      tenant, queryable
- [ ] **S5 API access:** per-tenant tokens for machine clients (service accounts), scopes, rate
      limiting
- [ ] **S6 Logs and metrics:** structured logs with trace_id/span_id, request metrics; Loki (and
      maybe Prometheus/Mimir) in pcm's telemetry stack, with Grafana datasources
- [ ] **S7 File storage per tenant:** ActiveStorage with tenant-separated keys; an S3-compatible
      pcm service (e.g. Garage or MinIO)
- [ ] **S8 Tenant data lifecycle:** export, deletion (GDPR) and backup per tenant (one database
      per tenant makes this cheap)

Left to apps: billing; feature flags through flipper (appwork ROADMAP).

## D9 — UI: Phlex and RubyUI

Last, on purpose: it has the most long-term design implications. Open before it starts: its
scope, the visual baseline (fudge's shadcn tokens as they are, or another look), and whether ui
is only an installer or also ships shared runtime components (layout, nav, flash).

- [ ] The ui install generator as the home of fudge's setup (`apps/fudge`): its `phlex.rb` and
      `ruby_ui.rb` initializers, `Components::Base`/`Views::Base`, shadcn design tokens, the
      RubyUI component flow; a Tailwind `@source` line for each engine
- [ ] Phlex views for cognito's 503 page and tenanted's ERB views
- [ ] Later, for support and ui: fudge's `TableDefinition` (declarative columns, param allowlist,
      search and facets) and `Components::DataTable` (RubyUI DataTable, pagy), both marked there
      for "eventual home" in the gems
- [ ] When D9 has taken what it needs from `apps/` (single, multi, factory, fudge: the apps built on
      the earlier gems, broken since the move), the person removes it

## KIV

Kept in view, not scheduled:

- [ ] `db_tracing`: an opt-in telemetry setting for ActiveRecord spans (off by default; one span
      per query is noisy)

## Outside this repo

- [x] appwork (D8): gems renamed `appwork-<name>` / `Appwork::<Name>` (chatter, chorus, gtd,
      manager, okf) on partitia's names and contract; specs and RuboCop green (gtd's 8 board
      examples pending partitia-ui boards); see appwork's ROADMAP
- [ ] For appwork, in this repo: `Partitia::Support.component_tag` tags events by the first
      namespace segment, so appwork's are `partitia_appwork.*`, not `appwork_<name>.*`
- [x] For appwork, in the cnfs CLI: `cnfs engine check` takes the gem prefix from each gem dir's
      `<dir>/<prefix>-<dir>.gemspec` (was hard-wired to `partitia-`), so it runs on appwork too
- [ ] For appwork, in the cnfs CLI: `cnfs ci` can't bundle a repo whose gems come from gem-local
      (ruby-ci mounts only the repo)
- [ ] Gem distribution: generated apps' and appwork's lockfiles record this machine's gem-local
      path, so CI bundles unfrozen. Decide at the pause: publish to a gem server (pcm gemstash),
      git sources, or keep paths
- [ ] **Manual test (the person):** `CNFS_SECRETS_STORE=fnox cnfs services` against the real
      1Password vault through the space's service-account token. Only `fnox set --dry-run` and
      local providers have been tested; check the DSN lands in the vault, fnox exports
      `PARTITIA_TELEMETRY_ERROR_DSN` in the app dir, and `cnfs server` picks it up
- [ ] **What partitia needs from `anfs space setup` / `wsm setup`** (upcoming in anfs; filed as
      input, anfs r-20261022-4). For a space whose apps use `CNFS_SECRETS_STORE=fnox`:
      - a `fnox.toml` at the space root defining a 1Password provider authenticated by the
        space's service-account token (`OP_SERVICE_ACCOUNT_TOKEN`), with a known provider
        name `cnfs` can target (`CNFS_FNOX_PROVIDER`) and a vault per space
      - app dirs below it inherit that provider: an app's own `fnox.toml` (written by
        `fnox set` from `cnfs services`) holds only its keys
      - fnox's shell activation on cd, so `bin/rails c`, runners and jobs see the secrets, not
        only `cnfs server` (which wraps `fnox exec`)
      - non-interactive operation: with the token set, no 1Password unlock prompt, so agents
        can work in the space
