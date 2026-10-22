# AGENTS.md — partitia-support

Guidance for agents working **inside `partitia-support`**.

Read `../AGENTS.md` (the repo) first, and `../ARCHITECTURE.md` (the layers and the engine
contract). This file carries only what is specific to `partitia-support`.

When writing or updating this gem's `README.md`, follow the **readme-authoring**
skill; for its config/logging/telemetry primitives follow the matching skills —
`partitia-support` is where those conventions are *implemented*, so keep the code and
the skill in step.

## What partitia-support is

The lean foundation gem for the CNFS family — the `active_support` analogue. It
holds the cross-cutting primitives every other `partitia-*` gem and every host app
can depend on freely, in any environment: the config base (`Partitia::Support::Config`,
anyway_config), the tagged per-component logging mixin, the notification-emitting
`Instrumentable` mixin, the family-wide redaction surface, the tenant
migration-path registry, and the railtie that wires `logger`/`instrument` into
every model and controller.

Its charter is **dependency-light and environment-agnostic**: the primitives are
usable pre-boot, before Rails loads, and cost nothing until a host opts in. That
charter is the boundary below — most of what makes this gem *this* gem is what it
deliberately refuses to depend on.

## Where the plans live

`partitia-support` carries **no gem-local `doc/plans`**. What it was built from is in the
archived space-level plans (`../../doc/archive/plans`: `005-diagnostic-logging`,
`006-config-adoption`, `008-telemetry-enrichment-dashboards`); new work comes from
`../ROADMAP.md`. `progress.md` here is the append-only completion log.

## Testing

`bundle exec rspec` at the gem root (plain RSpec, no dummy app — the primitives
are unit-testable without Rails). The suite exercises the degrade paths (Rails
absent, OTel absent) directly, which is why it must stay Rails-free to run.

## #coherence

<!-- level: project -->

The durable design claims this gem stands behind. Each is a decision no passing
spec captures; `docs-patrol` checks these for drift. Severity drives the drift
score — kept honest, `[critical]` is boundary/identity only. A `referent` says
how a later session would know the claim stopped being true.

### boundary

- [critical] `partitia-support` carries **no runtime dependency on Rails**. Its
  primitives are usable pre-boot and in non-Rails contexts; Rails is used only
  when already present (the Railtie is defined only under
  `defined?(Rails::Railtie)`; the logging backend degrades to a stdlib `Logger`
  when Rails is absent).
  referent: the gemspec's `add_dependency` list is `activesupport` +
  `anyway_config` only (Rails is `add_development_dependency`); no `lib` file
  `require`s Rails at load time; docs describe the pre-boot/degrade charter.
- [critical] `partitia-support` carries **no runtime dependency on OpenTelemetry**.
  The emit path reaches OTel *only* through a runtime `defined?(OpenTelemetry)`
  probe — never a `require`, never a load-time constant reference — so the gem is
  inert until a host runs `partitia-telemetry` + an OTel SDK.
  referent: no `lib` file `require`s any `opentelemetry-*`; every OTel touch
  (`Logging#bridge_span`, `Instrumentable.set_span_context`) sits behind
  `defined?(OpenTelemetry)`; the gemspec declares no opentelemetry runtime dep.

### identity / structure

- [high] One component-tag rule unifies a gem's log tag and its instrumentation
  name. `Partitia::Support.component_tag` derives `<component>` from the first namespace
  segment (partitia-prefixed); **both** `Logging` (the tag) and `Instrumentable` (the
  event name `<component>.<class>.<verb>`) key off it, so a gem's logs and traces
  share one identifier by construction and cannot drift apart.
  referent: `Instrumentable.event_name`'s component half equals
  `Partitia::Support.component_tag` for the same class; docs describe the single shared
  identifier as the reason the two align.
- [high] `Instrumentable` emits plain `ActiveSupport::Notifications` and creates
  **no spans of its own** — it knows nothing about tracing. The
  notification→span bridge lives in the separate `partitia-telemetry` gem, which
  subscribes to the `<component>` prefix. What OTel touch exists here only
  *annotates* an already-active span (`set_span_context`, the log-bridge event),
  never opens one.
  referent: no tracer/span *creation* anywhere in `lib`; docs place the
  notification→span bridge in `partitia-telemetry`, not here.
- [high] `Logging` is a thin, independent layer — tag + per-tag level + swappable
  backend — **not** a wrapper over `ActiveSupport::TaggedLogging`/`BroadcastLogger`.
  Per-tag verbosity (a `levels` registry with a `:default` floor) is the
  capability a single global Rails logger level cannot provide, and is the reason
  the layer is independent.
  referent: `Logging` neither includes nor wraps `TaggedLogging`; it keeps its own
  per-tag `levels` registry; docs describe the layer as independent and say why.
- [high] The Railtie injects `logger` **and** `instrument` into every
  `ApplicationRecord`, but injects `logger` **only** into every
  `ApplicationController` — controllers deliberately do **not** get `instrument`,
  because Rails/OTel already trace controller actions and auto-instrumenting them
  would double-trace.
  referent: the Railtie mixes `Instrumentable` into AR but not AC; docs state the
  controller/record asymmetry and the double-trace rationale.

### config & redaction

- [high] `Partitia::Support::Config` (an `Anyway::Config` subclass with singleton
  delegation) is the single config convention for the whole family: every gem's
  config surface derives from it, resolving YAML → credentials → ENV with one
  precedence, pre-boot and without Rails. Secrets resolve through that chain, not
  through source literals.
  referent: `Partitia::Support::Config < Anyway::Config` with `instance` delegation
  exists; the `config` skill designates it the canonical base; no secret is
  inlined in `lib`.
- [medium] The family-wide "never log / never attach as a span attribute" list is
  **config, not scattered constants**: `Partitia::Support::RedactionConfig` owns
  `DEFAULT_FIELDS`, extended by **merge** (`additional_fields` is unioned onto the
  defaults, never replacing them). It is the single source of what counts as a
  sensitive field.
  referent: `Partitia::Support::RedactionConfig < Config` exists with `DEFAULT_FIELDS` +
  `additional_fields` merged in `sensitive_fields`; the `logging`/`telemetry`
  skills point redaction here.

### coherence of docs ↔ plans

- [medium] This gem holds **no gem-local `doc/plans`** — its build is driven by
  the space-level cross-gem plans (now archived in `../../doc/archive/plans`), and `progress.md` is the
  completion log. Every plan reference in `progress.md` resolves to a real file
  under `../../doc/archive/plans`; no doc references a deleted file or a superseded rule.
  referent: `doc/` here has no `plans/`; grep of `progress.md`'s plan refs
  (`003`/`006`/`008`) resolves under `../../doc/archive/plans`; README tag examples match
  the actual `component_tag` output (`partitia_okf`, not `okf`).

### features in flux (provisional — not scored)

- **Redaction consumption**: `RedactionConfig.sensitive_fields` is read by partitia-telemetry's
  span bridge (sensitive payload keys never become span attributes) and by iam's and cognito's
  enrichment guards.