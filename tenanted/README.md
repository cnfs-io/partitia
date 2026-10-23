# Partitia::Tenanted

Optional multi-tenancy for Partitia Rails apps (ADR 0003), built on
[activerecord-tenanted](https://github.com/basecamp/activerecord-tenanted):
one SQLite database per tenant.

It provides:

- the **global plane**: a shared database holding the `Partitia::Tenanted::Tenant`
  registry;
- the **tenant plane**: one database per tenant, keyed by the tenant's immutable
  handle, provisioned when a `Tenant` is created, with an `after_provision` hook
  registry that other engines (iam) seed through;
- the reserved **platform** database (handle `platform`): never a tenant, reached
  only through `Partitia::Tenanted.with_platform`;
- request → tenant resolution (subdomain by default; host map and header
  resolvers included);
- the tenant registry UI (`/tenants`, the platform console) and the unknown-tenant
  page (`/tenant-unknown`), both ejectable;
- migration status across the global, platform and tenant databases.

The engine is not isolated: it draws `/tenants` and `/tenant-unknown` into the
app's routes, and the app subclasses its controllers.

## Install

```ruby
# Gemfile
gem "partitia-tenanted"
```

```bash
bundle install
bin/rails generate partitia:tenanted:install
```

The generator:

- writes `config/database.yml` with a `global` database and a `tenant` database
  (`tenanted: true`) in **every environment**, each taking its migrations from
  the registry (`<%= Partitia::Support.migrations_paths[:global] %>`,
  `[:tenant]`). It does this only when the file is missing or is still the stock
  file `rails new` wrote (production's Solid cache/queue/cable databases are
  kept). A file that already has the layout is left alone. A customized file
  without it stops the generator before anything is changed, with the layout to
  adopt printed;
- adds `tenanted "tenant"` to `ApplicationRecord` and
  `include Partitia::Tenanted::TenantResolution` to `ApplicationController`;
- sets `config.action_dispatch.tld_length = 0` in development, so
  `acme.localhost` resolves to subdomain `acme`;
- creates `TenantsController`, `TenantNotFoundController` and
  `config/initializers/partitia_tenanted.rb` if they don't exist;
- runs `db:migrate`, creating the global database;
- prints the entry points and what is left to do.

Every step is guarded: a second run changes nothing and asks nothing.

The `:tenant` (`db/migrate`) and `:global` (`db/global_migrate`) migration scopes
are registered by the engine; the app adds nothing for them.

### After install

1. Decide who may use the platform console: set
   `Partitia::Tenanted.platform_console_guard` (a callable run as a
   `before_action` in controller context). Unset, `/tenants` answers 403.
2. Provision the reserved platform database, once per environment:
   `Partitia::Tenanted.provision_platform!(owner_email: "you@example.com")`.
3. Create tenants:
   `Partitia::Tenanted::Tenant.create!(name: "Acme", subdomain: "acme", owner_email: "owner@acme.test")`,
   then visit `http://acme.localhost:3000`.

The tenant's database is selected at the Rack layer (activerecord-tenanted's
middleware, given `Partitia::Tenanted.request_handle`: the resolver, then the
`Tenant` lookup to its handle), so mounted engines such as partitia-cognito's
`/auth` run in the tenant's database with no app wiring: a sign-in on
`acme.localhost` lands in acme's database. A blank or unknown subdomain runs
untenanted, and the app's own routes redirect it to `/tenant-unknown`.

With partitia-cognito, a sign-in needs a selected database: the engine adds a
`Partitia::Cognito.before_sign_in` hook, so `/auth/login` (and `/auth/callback`)
on an unknown subdomain redirects to `/tenant-unknown`, and on the apex answers
404 ("sign in at your workspace's address"), both before the IdP. The apex is
not a sign-in (ADR 0003 §8: apex login asks for the workspace). The platform's
own sign-in is a host entry point that pins the reserved database for the round
trip, as the dummy's `/platform/login` does (`identity.rb`); its root's link
token is `bin/rails partitia:iam:bootstrap TENANT=platform`.

With partitia-telemetry (`rack_tracing`, on by default), every request's server
span carries `tenant.subdomain` and `tenant.handle`, set at the Rack layer.

With partitia-iam, each tenant's root principal is seeded on creation with a
bootstrap link token; `bin/rails partitia:iam:bootstrap TENANT=<subdomain>`
issues a fresh one for the first sign-in (partitia-iam's README). The console
guard is still the app's to set; `spec/dummy/config/initializers/identity.rb`
in this repo is a reference for it.

## Migrations

Migrations are read in place from the app and every registered engine through
`Partitia::Support.migrations_paths`; nothing is copied. Tenant-plane tables
live in `db/migrate`, global-plane tables in `db/global_migrate`. Tenant
databases are migrated when provisioned; `bin/rails db:migrate:tenant` (from
activerecord-tenanted) migrates existing ones, `bin/rails db:migrate` the global
database.

`partitia:tenanted:install:global_migrations` copies every engine's global
migrations into `db/global_migrate`, for an app that hardcodes
`migrations_paths` instead.

### Migration status

activerecord-tenanted has no status task for tenant databases, and its tenant
connections raise `PendingMigrationError` when a migration is pending. This one
reads each database through its own temporary connection, so pending migrations
show as `down`:

```bash
bin/rails partitia:tenanted:migrate:status                     # every database
ARTENANT=<handle> bin/rails partitia:tenanted:migrate:status   # one (also global, platform)
```

```
global: storage/development.sqlite3

 Status   Migration ID    Migration Name
--------------------------------------------------
   up     20260601033001  Create partitia tenanted tenants

platform (reserved): storage/development/platform.sqlite3
...

tenant ccjq42tq (acme): storage/development/ccjq42tq.sqlite3

 Status   Migration ID    Migration Name
--------------------------------------------------
   up     20260703120001  Create partitia iam accounts
  down    20260703120002  Create partitia iam principals

3 databases; pending: tenant ccjq42tq (acme) (1)
```

A database whose file doesn't exist yet is listed as `(database not created)`
and is not created.

## Customizing

Override actions in the host controllers (`TenantsController`,
`TenantNotFoundController`), calling `super` or replacing them.

Eject views into the app, where they take precedence over the gem's:

```bash
bin/rails generate partitia:tenanted:views tenants
bin/rails generate partitia:tenanted:views tenant_not_found
bin/rails generate partitia:tenanted:views            # both
```

## Console (with partitia-dev)

When partitia-dev is loaded, `rails console` gains `switch!("<handle>")` to enter
a tenant's database (`switch!` alone to leave), `Tenant` shortcuts under `t`,
and the current tenant in the prompt.

## Notes

- `tld_length = 0` is development-only; production resolves subdomains with the
  default `tld_length`.
- Request tracing is partitia-telemetry's (`rack_tracing`); tenanted only adds
  the tenant attributes to its server span.

## License

[MIT](https://opensource.org/licenses/MIT).
