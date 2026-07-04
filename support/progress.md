# cnfs_support — progress log

Append-only. Newest at the bottom.

---

## Log↔trace bridge (plan 03) — optional, opt-in, shipped

**Design** — correlate logs with traces by attaching each emitted log line as a
**span event** on the currently-active span, via the OTel **trace** API only.
Deliberately NOT the Ruby OTel **logs** signal: that signal is still at
*Development* maturity in the Ruby implementation (mid-2026), and — the decisive
reason — adopting it would force an OTel dependency into `cnfs_support`, whose
runtime charter is OTel-free (gemspec carries `activesupport` only). Span events
need no new dependency and make no bet on the logs pipeline.

**cnfs_support stays OTel-free.** The emit path reaches OpenTelemetry ONLY
through a runtime `defined?(OpenTelemetry)` probe — never a `require`, never a
load-time constant reference. Since the gem no longer pulls `opentelemetry-api`
itself (the old plan-02 tracer mixin was removed), `defined?(OpenTelemetry)` is a
*genuine* signal: it is true only when the host actually runs `cnfs_telemetry` +
an OTel SDK. Inert otherwise.

**Opt-in flag, default OFF.** `CnfsSupport::Logging.bridge_to_spans = true`
enables it. Off by default per the "defer speculative capability" rule.

**Where the hook lives (decided, not re-opened).** In
`lib/cnfs_support/logging.rb`'s `TaggedLogger` emit path, behind the `defined?`
guard — NOT in `cnfs_telemetry` reaching in to decorate the logger. Lighter
touch, whole emit path in one file, and the `defined?` guard keeps the coupling
compile-time clean / runtime-only active.

**Behavior — mirror.** When bridging fires it writes to the backend AND adds the
span event; logs still land in their normal sink. No `divert` mode (span-only)
built — speculative, not asked for.

**Whose span is active.** Spans are opened out-of-band by `cnfs_telemetry`'s
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

- `lib/cnfs_support/logging.rb`
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
- `spec/cnfs_support/logging_bridge_spec.rb` — the six cases: (1) flag OFF → no
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

**Green gate — both suites pass.** `cnfs_support` 27 examples / 0 failures
(21 prior + 6 bridge); `cnfs_telemetry` 14 / 0 (untouched). Rubocop clean on all
changed files.

**How to observe live** — in a booted dummy app that has `cnfs_telemetry` wired
(SDK + exporter), set `CnfsSupport::Logging.bridge_to_spans = true`, then run an
`instrument(:x) { logger.info "..." }` block: the subscriber's `Context.attach`
establishes the active span, and the `logger.info` line surfaces as a span event
(`log.severity` + `log.tag`) on that span in Tempo/Grafana. This integration
harness was NOT added to `cnfs_support`'s suite — `cnfs_telemetry` is not on this
gem's load path, and the plan says skip it rather than add a cross-gem dep; the
unit harness above satisfies the gate.
