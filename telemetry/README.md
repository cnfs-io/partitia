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
gem "partitia-telemetry"
```

```bash
bundle install
bin/rails g partitia:telemetry:install
```

The generator:
- adds `opentelemetry-sdk` + `opentelemetry-exporter-otlp` to the Gemfile (the
  host owns the SDK) and bundles, via `bundle add` — idempotent, so re-running is
  safe.
- ejects `config/initializers/opentelemetry.rb` — app-owned SDK config + exporter,
  and the `Partitia::Telemetry.install!` call that attaches the bridge. Edit freely.

The telemetry stack itself is **external** — bring up a collector/Tempo/Grafana
stack (e.g. the shared one at `chorus/services/telemetry`, `podman compose up`)
and traces export there over OTLP (`localhost:4318`); view them in Grafana at
http://localhost:8080.

The `Railtie` calls `Partitia::Telemetry.install!` on boot regardless; the explicit
call in the initializer just keeps the wiring visible next to the SDK config it
depends on. Both are idempotent.

## Configuration

`Partitia::Telemetry.prefixes` (default `%w[partitia]`) controls which event-name families
the bridge subscribes to. The single `partitia` prefix captures the whole family
because every component underscores to `partitia_*`. A host can append its own before
`install!` runs:

```ruby
Partitia::Telemetry.prefixes << "myapp"
```

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
(subscriber → SDK → collector → Tempo → Grafana), bring up the external telemetry
stack (e.g. `chorus/services/telemetry`, `podman compose up`) and exercise an
instrumented path. For example, creating an OKF bundle emits
`partitia_okf.bundle.create`:

```ruby
# rails console
Partitia::Okf::Bundle.create!(path: "/some/okf/bundle", dev: some_dev)
```

Then in Grafana (http://localhost:8080) → Explore → Tempo, search for
`partitia_okf.bundle.create`. The span carries the block's duration and its payload
as attributes (`partitia_okf.bundle.create.bundle_id`, …). Stack spin-up,
troubleshooting, and a no-app synthetic-span smoke test live in the stack's own
README.

## License

Available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
