# partitia-telemetry — progress log

Append-only. Newest at the bottom.

---

## Bootstrap — notification->span bridge, generator, first okf target

**Design** — the ratified notification-bridge (not CC's direct-tracer mixin,
which was removed from partitia-support). Every CNFS gem emits plain
`ActiveSupport::Notifications` events under a tag-prefixed name
(`okf.bundle.create`); this gem is the ONLY place that knows OpenTelemetry. It
subscribes to those prefixes and turns each event into a span on the OTel API
tracer. Depends on `opentelemetry-api` + `opentelemetry-semantic_conventions` +
`activesupport` — never the SDK.

**What shipped**

- `lib/partitia/telemetry.rb` — `Partitia::Telemetry.install!` / `uninstall!` / `prefixes`
  (default `%w[cnfs okf chorus iam]`). Idempotent install.
- `lib/partitia/telemetry/subscriber.rb` — the bridge. Object-form AS::N subscriber:
  opens a span in `#start`, attaches it to the OTel context (so nested events and
  host Rack/Rails auto-instrumentation nest correctly), closes it in `#finish`.
  Event name = span name; first dotted segment = tracer name (matches
  Partitia::Support::Logging's component tag). Payload entries become
  `<event>.<key>` attributes; `:exception`/`:exception_object` mark span error.
- `lib/partitia/telemetry/railtie.rb` — calls `install!` after
  `:load_config_initializers` so a host initializer can tweak `prefixes` first.
- `lib/generators/partitia/telemetry/install/` — `rails g partitia:telemetry:install`
  ejects `config/initializers/opentelemetry.rb` (app-owned SDK config + exporter
  + `install!`) and a `telemetry/` compose stack (ported verbatim from
  partitia-support's proven `doc/plans/stack/`: collector→tempo←grafana, up.sh/down.sh
  with apple|podman runtime selection). `--stack_dir` overrides the eject dir.
- `spec/` — RSpec harness + `support/otel_sdk.rb` (in-memory SDK capture, moved
  from partitia-support). `subscriber_spec.rb` covers: no-op path, span emission,
  attribute folding, tracer naming, nesting, error status, prefix scoping.

**Emit side proven target** — `partitia_okf`'s `Bundle#create_concepts` (the
`after_create` callback) now wraps its work in
`ActiveSupport::Notifications.instrument("okf.bundle.create", ...)`, adding a
`concept_count` to the payload. No OTel dep added to okf.

**Removed from partitia-support** — `lib/partitia/support/instrumentation.rb`, its spec,
the OTel gemspec deps, and the `require`. Logging stays (correctly placed, no
OTel). Dead files parked in `partitia/support/.trash/` pending `rm`. The original
`doc/plans/stack/` remains as reference until the ejected copy is verified live.

**NOT yet verified live** — the suite and the end-to-end span-in-Grafana path
have not been run (built from a filesystem-only session). Run steps in the chat
handoff.

**Open decision flagged** — prefix/naming convention. Went with bare-tag names
(`okf.bundle.create`, tracer `okf`) to match the proven stack data and the
logging component tag. If the `cnfs_<gem>` naming from the earlier chat summary
is wanted instead, `prefixes` and `tracer_for`'s split change.

---

## Naming convention resolved + emit ceremony moved to partitia-support

**Suite passing** on the first bootstrap (user ran it). Then two changes:

**1. component_tag refactor (user).** `Partitia::Support.component_tag` now returns
`deconstantize.underscore`, so `"Partitia::Okf::Bundle"` => `"partitia_okf"` (the module,
not a bare first segment). This exposed that the telemetry subscriber never
actually used that seam — it re-split the event name — and that the two derived
different identifiers. Resolved by standardizing the whole family on one
convention: **`<component>.<class>.<verb>`**, e.g. `partitia_okf.bundle.create`.

**2. New `Partitia::Support::Instrumentable` concern owns the notification ceremony.**
Emitters no longer hand-type event names. `include Partitia::Support::Instrumentable`
then `instrument(:create, **payload) { ... }`; the concern composes the name from
`self.class` — `component_tag(name)` for the component (so it matches the log
tag by construction) + demodulized-underscored class + the explicit verb. Verb is
explicit, NOT sniffed from `caller` (unreliable inside AR callbacks/blocks —
reads `"block in ..."`). Instance + class-level entry points. Lives in
partitia-support (no OTel dep on emitters); spec added.

**Ripple changes in partitia-telemetry:**
- `prefixes` default `%w[cnfs okf chorus iam]` -> `%w[cnfs]`. Single prefix now
  covers the family because every component underscores to `cnfs_*`.
- **Prefix-matcher bug fixed.** Old matcher `/\Acnfs(\.|\z)/` did NOT match
  `partitia_okf.bundle.create` — the `_` after `cnfs` is neither `.` nor end. New
  matcher `/\Acnfs[^.]*(\.|\z)/` matches the whole first segment regardless of
  the underscored tail. Spec added to guard this exact case.
- `tracer_for` unchanged in logic (still first dotted segment) but now yields
  `partitia_okf` because the segment itself changed. Comments/README updated.
- Subscriber spec rewritten to the new naming.

**okf Bundle** now uses `include Partitia::Support::Instrumentable` +
`instrument(:create, ...)` instead of the hand-typed
`ActiveSupport::Notifications.instrument("okf.bundle.create", ...)`.

**Generator now ejects a durable README** into the stack dir (spin-up, the
Grafana-won't-boot caveat, and the curl->collector + Tempo `/api/traces`
readback fallback, ported from partitia-support's proven progress notes). Post-
install output points at it instead of dumping steps that scroll away. Top-level
gem README replaced (was boilerplate) with architecture + emit/install docs.

**NOT yet verified live after these changes** — suite needs a re-run (both gems);
end-to-end span path unchanged in shape but the event name is now
`partitia_okf.bundle.create`.

---

## Meta-concern, console debug toggle, matcher confirmed loose

Three follow-ups from the user:

**1. Prefix matcher stays LOOSE.** Confirmed `/\Acnfs[^.]*(\.|\z)/` matches both
bare `cnfs` (via `\z`) and `cnfs_*` (via the `_okf` tail then `.`). It also
matches any first segment merely starting with `cnfs` (e.g. `cnfsxyz`) — accepted
as harmless for a closed gem family. Strict alternative `(_[^.]+)?(\.|\z)` noted
but not taken, per user.

**2. `Partitia::Support::Model` meta-concern (new).** `lib/partitia/support/model.rb` — an
ActiveSupport::Concern bundling `Logging` + `Instrumentable`, so a gem/app
`ApplicationRecord` includes ONE thing:

    class ApplicationRecord < ActiveRecord::Base
      include Partitia::Support::Model
    end

Applied to `partitia_okf`'s ApplicationRecord (replacing its bare
`include Partitia::Support::Logging`); removed the now-redundant
`include Partitia::Support::Instrumentable` from `Bundle` (inherited via base). New
concerns get added to Model once and all consumers pick them up. Spec added.

**3. Console `debug!` toggle (new).** `lib/partitia/telemetry/pry_console.rb` —
`Partitia::Telemetry::PryConsole.toggle!` attaches/detaches a subscriber that logs
every cnfs notification as published. Wholly independent of the OTel bridge /
SDK / collector / container: it is the "are my events firing?" probe. Registered
as a bare console command via partitia-dev's `Partitia::Dev.console { |c| c.command(:debug!)
{ ... } }` DSL (guarded by `defined?(Partitia::Dev)` at the bottom of
lib/partitia/telemetry.rb, so no hard dep). In `single`'s Gemfile partitia-dev loads
before partitia-telemetry, so the guard resolves. `debug!` toggles on/off and echoes
state. Spec added. README section added.

The debug tap uses a looser starts-with matcher than the bridge (intentional —
a diagnostic wants to see everything cnfs-ish).

**Still not run live** — both suites need a re-run; console `debug!` needs a
manual console check in `single` (can't exercise Pry from the filesystem session).

---

## Generator stops ejecting a stack; adds SDK gems instead

Docker services are now managed by an external toolset (the shared
`chorus/services/telemetry` stack, run via `podman compose`), so the gem no
longer ships or ejects its own compose stack.

**Removed from the install generator** — `eject_stack`, `make_scripts_executable`,
the `stack_dir` method + `--stack_dir` class_option, and every reference to
`stack/` / `up.sh` / `localhost:3000`. The `templates/stack/` source dir never
existed in this tree, so `eject_stack`'s `directory "stack", ...` would have
raised at runtime — the path was already dead. No generator spec existed, so
nothing broke.

**Added** — `add_sdk_gems` runs `bundle add opentelemetry-sdk
opentelemetry-exporter-otlp` (before `create_initializer`), following the
Rails/`bundle add` convention that a generator editing the Gemfile also installs.
Idempotent, keeps the lockfile correct, and the app boots after install without
the previous manual "add these gems yourself" step. Post-install output now
points at the external stack + Grafana on `http://localhost:8080`.

**Docs repointed** — `opentelemetry.rb.tt` (no more `<%= stack_dir %>`), gemspec
description, and README ("Installing", "Seeing spans end to end") now describe the
external stack (`podman compose up`, Grafana `:8080`) instead of an ejected one.
The service-side README lives with the stack at `chorus/services/telemetry`.

---

## D3 — engine contract (ARCHITECTURE §2, §4, §5, §7, §9, Q2)

- Depends on partitia-support (gemspec + Gemfile path). Still Rails-free at load.
- Span bridge drops any payload key in `RedactionConfig.sensitive_fields`.
- `Partitia::Telemetry::Config` (`partitia_telemetry`): `service_name`,
  `otlp_endpoint` (`http://localhost:4318`), `error_dsn`, `prefixes`. OTEL_* wins
  for the SDK (`sdk_service_name` / `sdk_traces_endpoint` return nil).
- Generator idempotent: adds only missing gems (now also `sentry-rails`), skips
  existing initializers; writes `sentry.rb` (on only with `error_dsn`); OTel
  initializer reads the config, no literals. Prints the remaining steps.
- Boot warns once when the SDK isn't configured.
- `partitia.services = "telemetry glitchtip"`.
- Specs 14 → 35; rubocop clean.
