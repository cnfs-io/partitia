# partitia-support — progress log

Append-only. Newest at the bottom.

---

## Log↔trace bridge (plan 03) — optional, opt-in, shipped

**Design** — correlate logs with traces by attaching each emitted log line as a
**span event** on the currently-active span, via the OTel **trace** API only.
Deliberately NOT the Ruby OTel **logs** signal: that signal is still at
*Development* maturity in the Ruby implementation (mid-2026), and — the decisive
reason — adopting it would force an OTel dependency into `partitia-support`, whose
runtime charter is OTel-free (gemspec carries `activesupport` only). Span events
need no new dependency and make no bet on the logs pipeline.

**partitia-support stays OTel-free.** The emit path reaches OpenTelemetry ONLY
through a runtime `defined?(OpenTelemetry)` probe — never a `require`, never a
load-time constant reference. Since the gem no longer pulls `opentelemetry-api`
itself (the old plan-02 tracer mixin was removed), `defined?(OpenTelemetry)` is a
*genuine* signal: it is true only when the host actually runs `partitia-telemetry` +
an OTel SDK. Inert otherwise.

**Opt-in flag, default OFF.** `Partitia::Support::Logging.bridge_to_spans = true`
enables it. Off by default per the "defer speculative capability" rule.

**Where the hook lives (decided, not re-opened).** In
`lib/partitia/support/logging.rb`'s `TaggedLogger` emit path, behind the `defined?`
guard — NOT in `partitia-telemetry` reaching in to decorate the logger. Lighter
touch, whole emit path in one file, and the `defined?` guard keeps the coupling
compile-time clean / runtime-only active.

**Behavior — mirror.** When bridging fires it writes to the backend AND adds the
span event; logs still land in their normal sink. No `divert` mode (span-only)
built — speculative, not asked for.

**Whose span is active.** Spans are opened out-of-band by `partitia-telemetry`'s
subscriber, which `Context.attach`es each span for the extent of an
`instrument(...)` block. So a `logger.info` inside such a block sees that span
via `Trace.current_span` automatically — no inline tracer. The active span is the
nearest enclosing `instrument(...)` (or a host Rack/Rails request span, or none).
A line can therefore ride a span from a *different* component; the
`log.tag` attribute preserves the line's own identity, so it is necessary, not
decorative. When nothing is active, `current_span` is the API no-op span,
`recording?` is false, and the guard silently skips — the common case, not an
error.

**What shipped**

- `lib/partitia/support/logging.rb`
  - `Logging.bridge_to_spans` accessor (default `false`), reset in `reset!`.
  - `TaggedLogger#bridge_span(message, level)` — private; `defined?` probe →
    `Trace.current_span` → `recording?` gate → `span.add_event(message,
    attributes: { "log.severity" => level, "log.tag" => @tag })`. Called from the
    generated level methods only when `bridge_to_spans`. The message block is
    evaluated exactly once and reused for backend line + span event. The level
    filter (`enabled?`) gates the bridge too — a suppressed line is neither
    logged nor bridged, and its block is never evaluated.
- `spec/support/otel_span_capture.rb` — SDK-backed capture helper (dev/test
  only). Configures an in-memory exporter + simple processor, `with_active_span`
  opens a recording span and `Context.attach`es it (mirrors the subscriber),
  `last_span_events` reads events off the finished span. `opentelemetry-sdk` was
  already a dev/test Gemfile dep; **no runtime/gemspec dep added**.
- `spec/partitia/support/logging_bridge_spec.rb` — the six cases: (1) flag OFF → no
  events; (2) flag ON + recording span → event with `log.severity`/`log.tag`;
  (3) flag ON + `OpenTelemetry` hidden (`hide_const`) → no raise; (4) flag ON +
  no active recording span → silent, no raise; (5) flag ON + span from another
  component → `log.tag` still the line's own; (6) below-threshold line → neither
  logged nor bridged, block not evaluated.
- `spec/spec_helper.rb` — resets `OtelSpanCapture` between examples.

**Step 0 baseline** — the earlier-refactor failures the plan warned about
(missing `active_support/isolated_execution_state` require in `instrumentable.rb`;
`Logging`/`Instrumentable` not propagating class methods through `Model`) were
already fixed in the tree: both are `ActiveSupport::Concern`s with `class_methods`
blocks and the require is present. Baseline was green before bridge work.

**Green gate — both suites pass.** `partitia-support` 27 examples / 0 failures
(21 prior + 6 bridge); `partitia-telemetry` 14 / 0 (untouched). Rubocop clean on all
changed files.

**How to observe live** — in a booted dummy app that has `partitia-telemetry` wired
(SDK + exporter), set `Partitia::Support::Logging.bridge_to_spans = true`, then run an
`instrument(:x) { logger.info "..." }` block: the subscriber's `Context.attach`
establishes the active span, and the `logger.info` line surfaces as a span event
(`log.severity` + `log.tag`) on that span in Tempo/Grafana. This integration
harness was NOT added to `partitia-support`'s suite — `partitia-telemetry` is not on this
gem's load path, and the plan says skip it rather than add a cross-gem dep; the
unit harness above satisfies the gate.

## Plan 006 — Config adoption (redaction surface + family audit)

**WS3 — redaction/PII config surface.** New
`Partitia::Support::RedactionConfig < Partitia::Support::Config`
(`config_name :partitia_redaction`, `lib/partitia/support/redaction_config.rb`, wired
into `partitia_support.rb`). It owns the family-wide "never log / never attach as a
span attribute" list as **config, not scattered constants**:
- `DEFAULT_FIELDS` — `sub`, `subject`, `email`, `access_key_id`, `principal_id`,
  session ids (`session_id`, `sid`, `session`), and the OIDC/secret token names
  from the logging/telemetry redaction rules (`id_token`, `access_token`,
  `refresh_token`, `code`, `code_verifier`, `client_secret`, `secret`,
  `password`, `hmac_key`).
- **Extensible (merge, not replace):** `additional_fields` (via
  `PARTITIA_REDACTION_ADDITIONAL_FIELDS`, `config/partitia_redaction.yml`, or
  credentials) is unioned onto the defaults — the defaults are always retained.
- Readers `sensitive_fields` (deduped symbols, matching `instrument(...)` payload
  keys) and `sensitive_field?(name)`. Guards assert
  `payload.keys & Partitia::Support::RedactionConfig.sensitive_fields == []`.

This WS **defines** the surface only; **Plan 008 consumes** it in the enrichment
guards. `spec/partitia/support/redaction_config_spec.rb` proves defaults, predicate,
merge-extension, dedup, and the intersection guard shape → 5 examples.
`bundle exec rspec` → 36 examples, 0 failures. `bundle exec rubocop` → clean.

**WS1 — family audit (recorded here for the gems with no change of their own).**
Migrated: `iam`, `partitia-cognito` (see their progress logs). Zero config:
`chorus`, `okf`, `partitia-dev`. Reviewed and deliberately **left as module
accessors** (data-vs-slot test: none is a secret, an `ENV.fetch`, or a value the
deploy env sets through the chain — all are structural/hot-path wiring):
- `chatter#parent_controller` — class-name string constantized at eager-load,
  set in a host initializer *before* controllers load (turbo-rails pattern);
  lazy anyway_config would break that timing. Its `participant_candidates` is a
  slot (callable).
- `partitia-tenanted#platform_table_prefixes` — structural allowlist tied to mounted
  engines, on the platform-context security path (its `tenant_resolver`,
  `tenant_not_found_handler`, `platform_console_guard` are slots).
- `partitia-telemetry#prefixes` — subscription wiring read once at `install!`,
  extended via the `prefixes << "x"` mutate idiom.
- `partitia/support/logging#{levels,bridge_to_spans}` — foundation logging state read
  on the per-log-line hot path; per the logging skill, per-tag levels and the
  log↔trace bridge are the host-app's logging concern, not chain config
  (`backend` is a slot). No secrets anywhere in these gems.

---

## Partitia::Support walker + source paths (PLAN-cnfs-support-walker-and-cleanup, Part A)

**What shipped**

- `Partitia::Support.each_plugin` — THE single Rails-first, Engine-guarded plugin walk.
  Yields `Rails` (host) first so its paths win in any ordered collection, then
  each registered plugin, raising unless it is a `Rails::Engine`. `enum_for`
  guard so `each_plugin.map(&:root)` works block-less.
- `set_migrations_paths_from` — added a duplicate guard (was appending
  unconditionally; a double boot in one process doubled paths).
- `source_paths_for` / `source_paths` / `set_source_paths_from` — new collection
  of every plugin`\s Tailwind-scannable dirs (`app/views`, `app/helpers`,
  `app/components`), ABSOLUTE by design, idempotent.
- `railtie.rb` — `:set_migrations_paths` refactored onto `each_plugin`
  (behavior-preserving; `|app|` dropped) plus a sibling `:set_source_paths`
  initializer riding the same walker.

**Decisions worth flagging**

- The migrations initializer refactor is pure: the dummy still migrates
  (`db:drop/create/migrate` → both migrations `up`, engine `Create okf schema`
  among them), proving the walker matches the old inline loop.

**How to run**

```
bundle exec rspec            # 46 examples (9 new across each_plugin/source_paths/migrations_paths specs)
bin/rubocop lib spec/partitia-support
```

---

## Shell streaming — `Partitia::Support::Shell.stream` (plan 001) — shipped

**What shipped**

- `Partitia::Support::Shell.stream(*argv, cwd:, idle_timeout:, sensitive:, env:, &block)`
  — a sibling to `run` for driving a long-running child that emits output
  incrementally (a coding-agent CLI streaming NDJSON). Yields each stdout line
  chomped **as it arrives**, accumulates full stdout on the Result, drains
  stderr on its own thread (popen3 deadlock guard), and returns the same
  normalized `Shell::Result`. Block is required (else ArgumentError — use `run`).
- **popen3, not mixlib.** Deliberate, documented exception to "everything goes
  through mixlib": mixlib gives no child handle (no INT/KILL), blocks until exit,
  and only does wall-clock timeouts. The single-swap-point invariant is still
  satisfied — one class, one gem.
- **Idle timeout, not wall-clock** (`idle_timeout:`, default 300s). `IO.select` +
  `read_nonblock` (buffer-free so select stays truthful); each read resets the
  clock. A silent child is killed; a chatty long-running one is not.
- **INT→KILL escalation** on both idle timeout and Ctrl+C. Interrupt marks the
  Result `interrupted: true`, then re-raises so the program still stops — the
  partial Result rides the re-raised exception (`rescue Interrupt => e; e.result`)
  via a `StreamInterrupt` mixin.
- **`Shell::Result` gained an `interrupted` member** (reads false when unset, so
  `run`'s construction and its specs are untouched).
- **Argv normalization extracted** to a shared private `normalize_argv` both
  `run` and `stream` call, so the argv discipline can't drift.
- Instrumentation `partitia_support.shell.stream`: secret-free payload with `lines`
  (count) + `interrupted`, never stdout/stderr; `sensitive:` redacts.

**Decisions worth flagging**

- **Process-group kill, not single-pid.** The child is spawned `pgroup: true` and
  signalled at `-pid` (the whole group). An agent CLI spawns its own children; a
  grandchild left alive keeps the stderr pipe open and the drain thread would
  block until it exits. `terminate` INTs, waits the grace, then KILL-sweeps the
  group unconditionally (leader may die on INT while a just-forked grandchild
  lingers); an empty group yields ESRCH, rescued as benign. This closes a real
  race the first cut had (interrupt test hung the full `sleep 5`).
- No `stream!` variant — a streaming caller already holds the Result in a
  block-structured flow.

**How to run**

```
bundle exec rspec            # 76 examples (15 new in shell_spec.rb .stream)
bin/rubocop lib spec/partitia-support
```

---

## Install generator wires every environment (ARCHITECTURE §5) — shipped

`partitia:support:install` now injects
`migrations_paths: <%= Partitia::Support.migrations_paths[:primary] %>` into the
primary database of development, test and production. Placement is read by
`Generators::DatabaseYml` (pure Ruby, line-based, no YAML round-trip, so comments
and ERB survive): a flat env block, or its `primary:` in a multi-database block;
after `database:`, else `url:`, else the block's last key (a commented-out
database). Anchored on structure, not on sqlite filenames.

- Idempotent per environment: a block already carrying the line is `identical`; a
  block with a different `migrations_paths` is never rewritten — reported instead.
- Can't place it (env missing, empty, multi-db without `primary:`): changes
  nothing there, says what to add and where, and repeats it in the closing
  "the host still has to" list. Keeps the `spec/dummy` fallback.
- Injection is bottom-up via `insert_into_file` anchored on the file's exact
  prefix (unique match); `force: true` there only defeats Thor's
  "text already somewhere in the file" skip.

**How to run**

```
bundle exec rspec   # 95 examples (17 new: spec/generators/, the generator ones in a child process to keep the suite Rails-free)
bin/rubocop
```
