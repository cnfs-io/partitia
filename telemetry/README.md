# Partitia::Telemetry

Bridges `ActiveSupport::Notifications` to OpenTelemetry for the CNFS gem family.

CNFS gems emit plain notifications and depend on nothing telemetry-related.
`partitia-telemetry` is the one place that knows about OpenTelemetry: it subscribes
to `partitia`-prefixed events and turns each into a span. It depends on the OTel
**API only** — until a host app installs and configures the SDK, the whole
bridge is a no-op, so gems can be instrumented freely with zero cost or
dependency imposed on consumers who don't want telemetry.

## Architecture

```
CNFS gem                     partitia-support                partitia-telemetry            host app
--------                     ------------                --------------            --------
include Instrumentable  -->  composes event name   -->   Subscriber turns    -->   OTel SDK
instrument(:create) { }      "partitia_okf.bundle.create"    the event into a          exports to
                             emits AS::Notification       span (API tracer)         collector
```

The naming convention is `<component>.<class>.<verb>`, e.g.
`partitia_okf.bundle.create`. The `<component>` is the underscored top-level module
(`partitia_okf`) — the *same* identifier `Partitia::Support::Logging` tags with — so a
gem's logs and traces share one name by construction. The subscriber uses that
first segment as the OTel tracer (instrumentation-library) name.

## Emitting events (in a CNFS gem)

The emit side lives in `partitia-support` so gems need no telemetry dependency. A
gem's `ApplicationRecord` includes `Partitia::Support::Model` once (which bundles
logging + instrumentation), and every model gets `instrument`:

```ruby
module Partitia::Okf
  class ApplicationRecord < ActiveRecord::Base
    include Partitia::Support::Model   # => logger + instrument on every model
    self.abstract_class = true
  end

  class Bundle < ApplicationRecord
    def create_concepts
      instrument(:create, bundle_id: id, path: path) do |payload|
        created = concept_paths.map { |p| concepts.find_or_create_by(path: p.to_s) }
        payload[:concept_count] = created.size   # enrich the payload -> span attributes
        created
      end
    end
  end
end
```

The block's duration becomes the span's duration. Payload entries become span
attributes (`partitia_okf.bundle.create.bundle_id`, etc.). An exception raised in the
block marks the span errored and re-raises. There is also a class-level
`instrument` for lifecycle work with no instance. (For a non-model class, include
`Partitia::Support::Instrumentable` directly instead of the `Model` bundle.)

## Installing in a host app

```ruby
# Gemfile
gem "partitia-telemetry"   # pulls in partitia-support
```

```bash
bundle install
bin/rails g partitia:telemetry:install
pcm up telemetry glitchtip
```

The generator:
- `bundle add`s `opentelemetry-sdk`, `opentelemetry-exporter-otlp`, `sentry-rails` and
  OTel's `opentelemetry-instrumentation-rack`, `-action_pack` and `-action_view` (the host
  owns the SDKs), skipping any already in the Gemfile.
- writes `config/initializers/opentelemetry.rb`: configures the OTel SDK from
  `Partitia::Telemetry::Config` (service name, OTLP endpoint, request tracing, below) and
  calls `Partitia::Telemetry.install!`.
- writes `config/initializers/sentry.rb`: `Sentry.init` from `error_dsn`, only when
  it is set; otherwise error reporting is off. It subscribes Sentry to the Rails error
  reporter (`config.rails.register_error_subscriber`, off in sentry-rails), so
  `Rails.error.report` and `Rails.error.handle` reach GlitchTip too.
- prints what is left: `pt services` (provisions GlitchTip's project and stores the
  DSN), or setting the DSN yourself.

It is idempotent: a second run adds no gems, leaves both initializers alone (once
written they are the app's; edit freely) and asks nothing. No endpoint or DSN is
written into the app. It prints what it added (or "Nothing added").

An app installed before request tracing existed is upgraded by re-running it: it adds the
three instrumentation gems and injects the `if Partitia::Telemetry::Config.rack_tracing`
block into the app's `OpenTelemetry::SDK.configure` block. A file that already mentions
`rack_tracing` is left alone; one with no such block gets the snippet printed to add by hand.

## Request tracing

With `rack_tracing` on (the default) the generated initializer `c.use`s OTel's standard
instrumentation:

- **Rack**: one `SERVER` span per request (`http.request.method`, `url.path`,
  `http.response.status_code`).
- **ActionPack**: names that span by route (`GET /up`, `GET /auth/login`) and adds
  `http.route`, `code.namespace` (the controller) and `code.function` (the action). It adds
  no span of its own.
- **ActionView**: `render_template`/`render_partial`/`render_layout` spans under it.

The bridge opens each `partitia_*` span in the current OTel context, so an engine's spans
(`partitia_cognito.sessions_controller.login_start`, …) are children of the request span,
one trace per request. ActiveRecord is not traced (that would be one span per query); add
`opentelemetry-instrumentation-active_record` and `c.use` it yourself if you want it.

These are hand-picked rather than `opentelemetry-instrumentation-rails`, which `use`s every
Rails instrumentation at once (ActiveRecord, ActiveJob, ActionMailer, ActiveStorage, …).

`PARTITIA_TELEMETRY_RACK_TRACING=false` (or `rack_tracing: false` in
`config/partitia_telemetry.yml`) turns request spans off: the instrumentation is never
`use`d, no middleware is inserted, and the `partitia_*` spans still export, each a root of
its own trace.

The `Railtie` calls `Partitia::Telemetry.install!` on boot regardless; the explicit
call in the initializer just keeps the wiring visible next to the SDK config it
depends on. Both are idempotent.

**Not a silent no-op.** If the gem is installed but the OTel SDK was never
configured (the generator wasn't run), boot logs one warning, tagged
`[partitia_telemetry]`:

```
OpenTelemetry SDK is not configured: partitia_* spans go nowhere. Run `bin/rails g partitia:telemetry:install` ...
```

## Services

The gemspec declares `spec.metadata["partitia.services"] = "telemetry glitchtip"`,
the pcm services this gem talks to: `stack/telemetry` (OTLP collector, Tempo,
Grafana) and `stack/glitchtip` (errors). `pcm show telemetry` / `pcm show glitchtip`
give their URLs.

## Dashboards

`dashboards/` holds the Grafana dashboards for the `partitia_*` spans, provisioned by
pcm's `stack/telemetry` (`pt services` points its `GRAFANA_DASHBOARDS_DIR` here; Grafana
rereads the dir every 30 s). Both query Tempo with TraceQL metrics (Tempo 3's
live-store: recent data only, no Prometheus) and filter on a `service.name` variable:

- **Partitia / Overview**: span rate, p95 latency, errored spans and spans per service,
  by event name; HTTP requests from the OTel server spans (`rack_tracing`): rate and p95
  latency by route, and rate by status code; the request span
  (`partitia_tenanted.telemetry_middleware.request`, with `config.partitia_tenanted.trace`);
  recent errored and slow traces.
- **Partitia / Identity**: sign-in outcomes and latency (cognito's callback), login
  starts, IdP calls, token verification and code exchange; iam's identity resolution
  and authorization gate; tenanted's tenant resolution, by outcome and by tenant.

An attribute is `<event name>.<payload key>` (`span.partitia_cognito.sessions_controller.callback.outcome`).
The app's requests have a span when `rack_tracing` is on (the default; see Request tracing).

## Configuration

`Partitia::Telemetry::Config` (a `Partitia::Support::Config`, `config_name
:partitia_telemetry`) holds the app's observability settings. Each resolves, in
ascending priority, from `config/partitia_telemetry.yml`, then
`credentials.partitia_telemetry`, then `PARTITIA_TELEMETRY_*`.

| Setting | ENV | Default | |
|---|---|---|---|
| `service_name` | `PARTITIA_TELEMETRY_SERVICE_NAME` | nil: the Rails app's module name, underscored (`MyShop::Application` → `my_shop`) | OTel `service.name` |
| `otlp_endpoint` | `PARTITIA_TELEMETRY_OTLP_ENDPOINT` | `http://localhost:4318` (pcm `stack/telemetry`) | OTLP/HTTP base URL; `/v1/traces` is appended |
| `error_dsn` | `PARTITIA_TELEMETRY_ERROR_DSN` | nil: error reporting off | GlitchTip/Sentry DSN. A secret: credentials or ENV only |
| `prefixes` | `PARTITIA_TELEMETRY_PREFIXES` (comma list) | `partitia` | event-name families the span bridge subscribes to |
| `rack_tracing` | `PARTITIA_TELEMETRY_RACK_TRACING` | `true` | request spans (Rack, ActionPack, ActionView; see Request tracing). A boolean: `false`, `0`, `no` turn it off |

`pt services` creates the app's GlitchTip project and stores its DSN
(`config/partitia_telemetry.local.yml`, gitignored, or fnox with
`PARTITIA_SECRETS_STORE=fnox`); `pt services --down` removes it again. By hand, get
it from GlitchTip (an organization and project, then the project's Client Keys) and
set it with `bin/rails credentials:edit`:

```yaml
partitia_telemetry:
  error_dsn: http://<key>@localhost:<glitchtip port>/<project id>
```

**OTEL_\* still wins for the OTel SDK** (OTel's convention):

- `OTEL_SERVICE_NAME` set: the SDK names the service; `service_name` is not passed.
- `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` or
  `OTEL_TRACES_EXPORTER` set: the SDK builds the exporter from ENV; `otlp_endpoint`
  is not used.
- `OTEL_SDK_DISABLED=true`: the SDK stays off (and the boot warning above fires).

`Config#sdk_service_name` and `Config#sdk_traces_endpoint` implement this (nil
means "leave it to the SDK"); the generated initializer reads them.

The bridge's prefixes are seeded from the config; a host can still append before
`install!` runs:

```ruby
Partitia::Telemetry.prefixes << "myapp"
```

## Redaction

The span bridge never attaches a payload key listed in
`Partitia::Support::RedactionConfig.sensitive_fields` (the family-wide list:
`email`, `sub`, `session_id`, `access_token`, `code`, `password`, …). It is dropped,
not masked. Extend the list with `PARTITIA_REDACTION_ADDITIONAL_FIELDS=ssn,dob` (or
`config/partitia_redaction.yml`); see partitia-support.

## With partitia-dev

When `partitia-dev` is present, the console gets the `notif!` toggle below.

## Watching events at the console (no stack required)

When `partitia-dev` is present, a `notif!` toggle is available at the Rails/Pry
console. It taps the notification bus directly and logs each partitia event as it is
published — independent of the SDK, the collector, and the container stack. Use
it to confirm the emit side is firing and to see payloads:

```
[1] pry> notif!
telemetry notif ON
[2] pry> Partitia::Okf::Bundle.create!(path: "...", dev: d)
[telemetry] partitia_okf.bundle.create (12.3ms) {:bundle_id=>1, :path=>"...", :concept_count=>4}
[3] pry> notif!
telemetry notif OFF
```

`notif!` is the toggle: call it to start watching, call it again to stop. It
echoes the resulting state each time. This is the fastest way to answer "are my
notifications even being published?" without standing anything up.

## Seeing spans end to end in Grafana

`notif!` proves the emit side; to watch a span travel the full pipeline
(subscriber → SDK → collector → Tempo → Grafana), bring up pcm's telemetry stack
(`pcm up telemetry`) and exercise an instrumented path. For example, creating an OKF bundle emits
`partitia_okf.bundle.create`:

```ruby
# rails console
Partitia::Okf::Bundle.create!(path: "/some/okf/bundle", dev: some_dev)
```

Then in Grafana (`pcm show telemetry` for its URL) → Explore → Tempo, search for
`partitia_okf.bundle.create`. The span carries the block's duration and its payload
as attributes (`partitia_okf.bundle.create.bundle_id`, …), under the app's
`service.name`. Stack spin-up and troubleshooting live in the pcm container's
README.

## License

Available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
