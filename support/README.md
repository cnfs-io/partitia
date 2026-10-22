# Partitia::Support

The lean foundation gem for the CNFS family — the `active_support` analogue. It
provides the dependency-light primitives every other CNFS gem and every host app
can depend on freely, in any environment: tagged per-component logging,
notification-based instrumentation, a config base, the family redaction surface,
and an engine migration-path registry.

`partitia-support` carries **no runtime dependency on Rails or OpenTelemetry**. The
primitives are usable pre-boot, before Rails loads; where a feature can use Rails
or OTel when present, it probes for them at runtime and degrades gracefully when
they're absent.

## Installation

```ruby
# Gemfile
gem "partitia-support"
```

```bash
bundle install
```

Requires Ruby >= 3.2.

## Automatic wiring in a Rails app

When Rails is present, the gem's railtie mixes the primitives in for you on boot,
so you rarely include them by hand:

- every `ApplicationRecord` (host app **and** every registered engine) gets
  `logger` **and** `instrument`;
- every `ApplicationController` gets `logger` (not `instrument` — Rails and OTel
  already trace controller actions).

```ruby
class Widget < ApplicationRecord
  def rebuild
    logger.info { "rebuilding #{id}" }             # logger — injected
    instrument(:rebuild, widget_id: id) do |payload|  # instrument — injected
      payload[:parts] = assemble.size
    end
  end
end
```

In a **non-Rails or pre-boot** context, or in a plain Ruby object, include the
mixin you want explicitly — that's the same API the railtie applies:

```ruby
class Report
  include Partitia::Support::Logging
  include Partitia::Support::Instrumentable
end
```

## Logging

Tagged, per-component logging with independent per-tag verbosity over a
host-swappable backend. Each including class gets a logger tagged with its gem's
name, derived from the first namespace segment (partitia-prefixed; for a
`Partitia::<Name>` constant the engine segment is used, so `Partitia::Iam::Credential`
logs under `partitia_iam`):

```ruby
module Okf
  class Button
    include Partitia::Support::Logging   # (auto-injected on ApplicationRecord in Rails)

    def render
      logger.debug { "rendering #{self.class}" }
    end
  end
end
```

`Okf::Button` logs under the tag `partitia_okf`. Use the block form
(`logger.debug { ... }`) for anything expensive — the block is skipped entirely
when the tag's level is disabled.

### Configuring it (host app)

Set the backend and per-tag levels once, in an initializer:

```ruby
Partitia::Support::Logging.backend = Rails.logger            # any Logger-like object
Partitia::Support::Logging.levels[:default] = :warn          # floor for all tags
Partitia::Support::Logging.levels["partitia_okf"] = :debug       # louder for one gem
Partitia::Support::Logging.levels["partitia_tenanted"] = :info
```

If no backend is set and Rails is absent, logging falls back to a plain `$stdout`
`Logger`, so the mixin works unchanged in non-Rails and pre-boot contexts.

`backend` accepts **any Logger-like object** — anything responding to the
standard `debug`/`info`/`warn`/`error`/`fatal` API (e.g. Semantic Logger, Ougai,
or a stdlib `Logger`). Because level filtering lives in the mixin (per tag), set
the chosen backend's own level permissively and let `Partitia::Support::Logging.levels`
do the per-gem gating so the two don't fight.

To mirror each log line onto the currently-active trace span as a span event,
opt in with `Partitia::Support::Logging.bridge_to_spans = true` — a no-op unless the
host also runs `partitia-telemetry` and an OTel SDK.

## Instrumentation

`Instrumentable` emits standardized `ActiveSupport::Notifications` events with no
telemetry coupling. You never hand-type an event name; it's composed from the
class and the verb you pass:

```ruby
module Partitia::Okf
  class Bundle
    include Partitia::Support::Instrumentable   # (auto-injected on ApplicationRecord in Rails)

    def create_concepts
      instrument(:create, bundle_id: id) do |payload|
        created = concept_paths.map { |p| concepts.find_or_create_by(path: p.to_s) }
        payload[:concept_count] = created.size
        created
      end
    end
  end
end
```

The event name follows one convention across the family —
`<component>.<class>.<verb>`, here `partitia_okf.bundle.create`. The `<component>`
half is the **same** identifier `Logging` tags with, so a gem's logs and traces
line up by construction.

These are cheap no-op notifications until something subscribes. If the host
installs `partitia-telemetry`, it subscribes to the `<component>` prefix and turns
each event into a span whose tracer name is that same `<component>`.

## Migration-path registry

Lets a host app collect the migration paths of many engines into a single
registry, so migrations run from their engines in place — without copying
migration files into the app. This is the mechanism the tenanted stack relies on
to inject per-database migration paths through `database.yml`.

**1. Register each engine that carries migrations.** Anywhere during boot (an
initializer, or an engine's own `engine.rb`), add the engine to the plugin set:

```ruby
Partitia::Support.plugins << MyEngine::Engine
```

Every registered engine must be a `Rails::Engine`. On boot, `partitia-support` walks
the registered plugins and builds the path registry for you.

**2. Reference the registry from `database.yml`.** Instead of hard-coding
`migrations_paths`, let the registry supply them via ERB:

```yaml
# config/database.yml
primary:
  adapter: sqlite3
  database: storage/primary.sqlite3
  migrations_paths: <%= Partitia::Support.migrations_paths[:primary] %>
```

If a database does **not** declare `migrations_paths`, Rails falls back to its
default (`db/migrate`). Declare it only when you want the engine paths folded in.

### Configuring which paths are collected

By default the registry collects one scope, `:primary`, from each engine's
`db/migrate`. Override the map to collect different or additional scopes — for
example a tenant-scoped path alongside a global one:

```ruby
# before engines are registered
Partitia::Support.migrations_paths_for.merge!(
  primary: "db/migrate",
  tenant:  "db/tenant_migrate"
)
```

Each key becomes an independently addressable scope
(`Partitia::Support.migrations_paths[:tenant]`) you can reference from the matching
entry in `database.yml`.

| Call | Returns |
|------|---------|
| `Partitia::Support.plugins` | the `Set` of registered engines; add to it to register |
| `Partitia::Support.migrations_paths_for` | the scope→search-path map (configurable) |
| `Partitia::Support.migrations_paths` | scope→collected-paths, built on boot |
| `Partitia::Support.migrations` | the flat list of every migration file found |

## Configuration

`Partitia::Support::Config` is the config base every CNFS gem's config surface derives
from (an `anyway_config` subclass). A gem defines one subclass per surface; values
resolve from `config/<name>.yml` → Rails credentials → ENV, with one precedence,
pre-boot and without Rails. Secrets resolve through that chain — never inline them
in source; use `rails credentials:edit` or the ENV var. See the `config` skill for
the full convention.

```ruby
module Partitia::Iam
  class Config < Partitia::Support::Config
    config_name :partitia_iam                      # config/partitia_iam.yml, credentials.partitia_iam, ENV["PARTITIA_IAM_*"]
    attr_config :issuer, session_ttl: 3600
  end
end

Partitia::Iam::Config.issuer        # singleton delegation — no explicit instantiation
```

### Redaction surface

`Partitia::Support::RedactionConfig` is the single source of truth for field names that
must never be logged or attached as span attributes. It ships `DEFAULT_FIELDS`
(identity, contact, session, and token names) and is extended by **merge** — a
host or gem adds names without re-listing the defaults:

```ruby
# config/partitia_redaction.yml → additional_fields: [ssn, date_of_birth]
# or ENV["PARTITIA_REDACTION_ADDITIONAL_FIELDS"] = "ssn,date_of_birth"

Partitia::Support::RedactionConfig.sensitive_fields        # DEFAULT_FIELDS ∪ additional_fields
Partitia::Support::RedactionConfig.sensitive_field?(:email) # => true
```

This gem **publishes** the list; the enrichment/redaction guards that consume it
live in `partitia-telemetry`.

## Development

Run the specs from the gem root — plain RSpec, no dummy app (the primitives are
unit-testable without Rails, and the suite exercises the degrade paths directly):

```bash
bundle exec rspec
```

## License

Available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).
