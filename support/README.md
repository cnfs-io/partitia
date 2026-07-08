# CnfsSupport

The lean foundation gem for the CNFS family — the `active_support` analogue.
It provides dependency-light primitives that every other CNFS gem and every host
app can depend on freely, in any environment.

`cnfs_support` deliberately carries **no runtime dependency on Rails**. Its
primitives are usable pre-boot, before Rails loads. Where a feature can use Rails
if it's present, it does so optionally and degrades gracefully when it isn't.

## Why these live in a gem

The observability features (logging, instrumentation) look lightweight, and their
_host-side configuration_ is — each app still writes its own initializer with its
own service name, exporter target, and level map, and that config is _supposed_
to vary per app. The value isn't in DRYing up that config.

The value is on the **emission** side, in the many gems the apps consume. `okf`,
`cnfs_tenanted`, and every future CNFS gem need to log and trace. Centralizing
that here buys three things per-app config cannot:

- **Per-gem verbosity.** A plain shared `Rails.logger` has one global level; the
  logging mixin lets a host turn `okf` up to `:debug` while keeping everything
  else quiet. That's a capability, not just less boilerplate.
- **Instrumentable-but-inert by construction.** Gems depend only on the OTel
  **API**, so every CNFS gem is a zero-cost no-op until a host installs the SDK —
  flip it on and they all light up, leave it off and they cost nothing. That
  contract lives in what the gems depend on, so it can't be expressed as app
  config.
- **One telemetry vocabulary.** Tag and tracer names derive from the gem's
  namespace (`Okf::Button` → `cnfs_okf`), so logs and traces line up under one
  identifier across every gem and every app — the difference between a readable
  cross-gem trace and a pile of anonymous spans.

This pays off precisely _because_ there's a family of shared gems feeding more
than one app. With a single app and a single gem, you'd skip the abstraction and
configure inline. The mixins stay intentionally thin: tag, level, swappable
backend, no-op-until-SDK — if they grow past that, they're drifting from
primitive toward framework.

## Installation

```ruby
# Gemfile
gem "cnfs_support"
```

```bash
bundle install
```

---

## Feature: Migration-path registry

Lets a host app collect the migration paths of many engines into a single
registry, so migrations run from their engines in place — without copying
migration files into the app. This is the mechanism the tenanted stack relies on
to inject per-database migration paths through `database.yml`.

### How a developer uses it

**1. Register each engine that carries migrations.** Anywhere during boot (an
initializer, or an engine's own `engine.rb`), add the engine to the plugin set:

```ruby
CnfsSupport.plugins << MyEngine::Engine
```

Every registered engine must be a `Rails::Engine`. On boot, `cnfs_support`
walks the registered plugins and builds the path registry for you.

**2. Reference the registry from `database.yml`.** Instead of hard-coding
`migrations_paths`, let the registry supply them via ERB:

```yaml
# config/database.yml
primary:
  adapter: sqlite3
  database: storage/primary.sqlite3
  migrations_paths: <%= CnfsSupport.migrations_paths[:primary] %>
```

If a database does **not** declare `migrations_paths`, Rails falls back to its
default (`db/migrate`) as usual. Declare it only when you want the engine paths
folded in. (If your workflow instead copies migrations from engines into the
app, just don't declare `migrations_paths` — the registry is for the
don't-copy workflow.)

### Configuring which paths are collected

By default the registry collects one scope, `:primary`, from each engine's
`db/migrate`. Override the map to collect different or additional scopes — for
example a tenant-scoped path alongside a global one:

```ruby
# before engines are registered
CnfsSupport.migrations_paths_for.merge!(
  primary: "db/migrate",
  tenant:  "db/tenant_migrate"
)
```

Each key becomes an independently addressable scope
(`CnfsSupport.migrations_paths[:tenant]`) you can reference from the matching
entry in `database.yml`.

### Reference

| Call | Returns |
|------|---------|
| `CnfsSupport.plugins` | the `Set` of registered engines; add to it to register |
| `CnfsSupport.migrations_paths_for` | the scope→search-path map (configurable) |
| `CnfsSupport.migrations_paths` | scope→collected-paths, built on boot |
| `CnfsSupport.migrations` | the flat list of every migration file found |

---

## Feature: Logging

Tagged, per-component loggers to replace scattered `Rails.logger.debug` calls
across CNFS gems. Each including class gets a logger tagged with its gem's name,
whose verbosity the host controls **independently per gem**, writing to a
backend the host can swap.

### How a developer uses it

Include the mixin in any class; call `logger`:

```ruby
module Okf
  class Button
    include CnfsSupport::Logging

    def render
      logger.debug { "rendering #{self.class}" }
    end
  end
end
```

The logger is tagged from the first segment of the class's namespace, so every
class under `Okf::` logs under the tag `cnfs_okf` (the first segment, cnfs-
prefixed). Use the block form
(`logger.debug { ... }`) for anything expensive — the block is skipped entirely
when the level is disabled.

### Configuring it (host app)

Set the backend and per-tag levels once, in an initializer:

```ruby
CnfsSupport::Logging.backend = Rails.logger            # any Logger-like object
CnfsSupport::Logging.levels[:default] = :warn          # floor for all tags
CnfsSupport::Logging.levels["cnfs_okf"] = :debug       # louder for one gem
CnfsSupport::Logging.levels["cnfs_tenanted"] = :info
```

If no backend is set and Rails is absent, logging falls back to a plain
`$stdout` logger — the mixin works in non-Rails and pre-boot contexts unchanged.

### Choosing a backend

`backend` accepts **any Logger-like object** — anything responding to the
standard `debug`/`info`/`warn`/`error`/`fatal` API. That's the whole seam: build
your preferred logger, assign it once, and every CNFS gem's output flows through
it. Beyond `Rails.logger` and the stdlib `Logger`, the three you're most likely
to reach for:

**Semantic Logger** — feature-rich, structured, asynchronous (logs on a
background thread), with many appenders (file, JSON, Graylog, Splunk, Syslog,
etc.). In a Rails app you'd normally add `rails_semantic_logger` to replace the
Rails logger wholesale; to point _just_ this gem at it, hand it an instance:

```ruby
require "semantic_logger"
SemanticLogger.default_level = :info
SemanticLogger.add_appender(io: $stdout, formatter: :json)  # or :color for dev

CnfsSupport::Logging.backend = SemanticLogger["cnfs"]
```

**Ougai** — a lighter structured logger that extends stdlib `Logger` and emits
JSON out of the box; a good fit when you want machine-readable logs without
Semantic Logger's surface area:

```ruby
require "ougai"
logger = Ougai::Logger.new($stdout)
logger.level = Ougai::Logger::INFO

CnfsSupport::Logging.backend = logger
```

**Lograge** — worth naming so you don't reach for it here: it restructures
Rails' _request_ logs into one tidy line and doesn't provide a general-purpose
logger object. Configure it in the host app the usual way
(`config.lograge.enabled = true`); leave `CnfsSupport::Logging.backend` on
`Rails.logger` and the two coexist — Lograge reshapes request logging while this
gem handles your gems' component logging.

Because the level filtering lives in the mixin (per-tag), set the chosen
backend's own level permissively (e.g. `:debug`/`:info`) and let
`CnfsSupport::Logging.levels` do the per-gem gating, so the two don't fight.

---

## License

Available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).
