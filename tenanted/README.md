# CnfsTenanted

Multi-tenant support for CNFS Rails apps, built on
[activerecord-tenanted](https://github.com/basecamp/activerecord-tenanted)
(a separate SQLite database per tenant).

It provides:

- a global **Tenant** registry (one shared database), carrying operator/admin-level tenant config;
- a per-tenant **Account** settings singleton (one row in each tenant's own database), carrying the tenant's self-service config;
- automatic tenant database provisioning when a `Tenant` is created;
- subdomain → tenant request resolution;
- Tailwind-styled MVC for both, rendered straight from the gem and ejectable into your app when you want to customize;
- a tenant-aware migration status rake task;
- a per-database migration-path setup (conventional copy-in by default, with an
  opt-in to read migrations in place from the gems).

---

## Prerequisites & assumptions

Read this before installing — the installer is invasive.

- **SQLite + activerecord-tenanted.** This gem assumes the database-per-tenant
  SQLite model. It is intended for **new apps**, or apps not yet committed to a
  database layout.
- **The installer rewrites `config/database.yml`.** It replaces your database
  config with a two-database (tenanted `tenant` + plain `global`) layout. If
  you have an existing, customized `database.yml`, back it up first.
- **A brief "won't boot" window during install.** Because install rewrites
  `database.yml` and adds a tenanted connection, the app is not expected to boot
  until you have completed install **and** run `db:migrate`. Don't try to start
  the server mid-install.
- Designed for **Rails 8.1+** and **Ruby 3.2+**.

---

## Installation

### 1. Add the gems

```ruby
# Gemfile
gem "cnfs_tenanted"
gem "activerecord-tenanted"   # the underlying per-tenant DB engine
```

```bash
bundle install
```

> `cnfs_tenanted` depends on `cnfs_support` (a lean foundation gem) automatically.
> The optional console helpers activate only if you also use `cnfs_dev` in
> development/test — they are not required.

### 2. Run the installer

```bash
bin/rails generate cnfs_tenanted:install
```

This wires your app for multi-tenancy. Specifically, it:

- calls `tenanted` in `app/models/application_record.rb` (every
  `ApplicationRecord` model becomes tenant-scoped);
- includes `CnfsTenanted::TenantResolution` in your `ApplicationController`
  (resolves the tenant from the request subdomain);
- rewrites `config/database.yml` (tenanted `tenant` + plain `global` DB);
- sets `config.action_dispatch.tld_length = 0` in development so
  `*.localhost` subdomains resolve;
- creates thin host controllers
  (`TenantsController < CnfsTenanted::TenantsController`, likewise for accounts)
  so routes resolve in your namespace and you can customize later;
- creates `storage/tenants/` for the per-tenant database files;
- runs `db:migrate` to create the **global** database (the tenant registry).

The installer is idempotent for the in-place edits — re-running it skips edits
that are already present — but it **force-overwrites `config/database.yml`**.

### 3. Verify the install (the sanity-check ladder)

Run these three checks in order. Each isolates one layer, so if something
breaks you know roughly where.

#### Check 1 — server boots, bare domain shows the (empty) tenant list

```bash
bin/rails server
```

Visit **http://localhost:3000**. You should see an empty **Tenants** list with a
"New tenant" button.

> Confirms: routing, the bare-domain constraint, and that the global database
> migrated (the `tenants` table exists). If this fails, look at
> `config/database.yml` and whether `db:migrate` created the global DB.

#### Check 2 — create a tenant in the console (the core test)

```bash
bin/rails console
```

```ruby
Tenant.create!(name: "Acme", subdomain: "acme")

# The real test — does the tenant DB exist, is it migrated, and was its
# Account settings singleton seeded with the tenant's name?
ApplicationRecord.with_tenant("acme") { Account.instance }
# => #<Account id: 1, name: "Acme", ...>
```

> Confirms the entire core: tenant database provisioning, the tenant DB
> migrating (the `accounts` table + its singleton constraint), the `with_tenant`
> context, and the `Account` singleton seeding. A new file should now exist at
> `storage/tenants/acme.sqlite3`.

You can also confirm the singleton is enforced:

```ruby
ApplicationRecord.with_tenant("acme") do
  Account.create!(name: "Second")   # expected to FAIL (singleton: only id 1 allowed)
end
```

#### Check 3 — subdomain shows the account settings page

Visit **http://acme.localhost:3000**. You should see the **Account settings**
page for the Acme tenant (name "Acme"), with an "Edit settings" link.

> Confirms: subdomain resolution, `tld_length`, and the subdomain root route
> (`accounts#show`). If you land on the tenant list instead, `tld_length` isn't
> taking effect.

If all three pass, the install is working.

---

## Day-to-day usage

### The two config models

| | Where | Who edits it | Surface |
|---|---|---|---|
| **Tenant** | global database | operator/admin | bare domain (`/tenants`) |
| **Account** | the tenant's own database (singleton) | the tenant | subdomain (`/account`) |

When a `Tenant` is created, its database is provisioned and its `Account`
singleton is seeded with the tenant's name. The two names then diverge freely —
the admin manages the `Tenant`, the tenant manages their `Account`.

### Console helpers (with `cnfs_dev`)

If `cnfs_dev` is loaded, the console gains:

```ruby
vst "acme"   # switch the console into the acme tenant's database context
vst          # clear back to the global/untenanted context

t            # => Tenant ;   ta / tc / tf / tl  (all / create / find / last)
a            # => Account ;  aa / ac / af / al
```

The prompt also gains a current-tenant segment while a tenant context is
active, e.g. `[development][acme] cnfs(main)>`.

### Tenant migration status

activerecord-tenanted ships `db:migrate:tenant` but no status task. This gem
adds one that works even when a tenant has pending migrations:

```bash
ARTENANT=acme bin/rails db:migrate:status:tenant   # one tenant
bin/rails db:migrate:status:tenant                 # every tenant
```

---

## Customizing (ejecting from the gem)

By default the tenant/account controllers and views are served **directly from
the gem** — you don't have copies in your app. When you want to customize, eject
the piece you care about; everything else keeps coming from the gem.

### Customize a controller

Your app already has thin host controllers from the installer. Override actions
there (call `super` or replace entirely):

```ruby
class TenantsController < CnfsTenanted::TenantsController
  def index
    super
    # ...your additions
  end
end
```

### Eject views

Copy a resource's views into your app, where they take precedence over the
gem's:

```bash
bin/rails generate cnfs_tenanted:views tenants    # just tenant views
bin/rails generate cnfs_tenanted:views accounts   # just account views
bin/rails generate cnfs_tenanted:views            # both
```

Once ejected, those views are yours; the gem's copies are no longer used for
that resource.

---

## Migrations: how they work

The gem ships two kinds of migration:

- **Global migration** (the `tenants` registry table) — runs against the
  `global` database.
- **Tenant migration** (the `accounts` singleton, plus anything your app or
  other engines add) — runs against each per-tenant database as it is
  provisioned.

There are two ways to source them, chosen per database in `config/database.yml`.
The installed file **defaults to copy-in** and carries the in-place alternative
commented out beside each database.

### Default: copy-in (conventional Rails)

Each database points at a normal path in your app (`db/migrate`,
`db/global_migrate`), so **your app owns its migrations**. Pull the gems'
migrations in the standard Rails way, then version them like any others:

```bash
bin/rails cnfs_tenanted:install:migrations          # TENANT migrations (db/migrate)
bin/rails railties:install:migrations               # every mounted engine's tenant migrations
bin/rails cnfs_tenanted:install:global_migrations   # GLOBAL migrations (db/global_migrate)
```

The first two are Rails' own engine-migration tasks; they only see the standard
`db/migrate` path, so they copy the **tenant** migrations. The **global**
migrations live under the non-standard `db/global_migrate` scope that Rails
doesn't know about, so `cnfs_tenanted:install:global_migrations` fills that gap
— it copies the global migrations of *every* registered CNFS engine into
`db/global_migrate` in one run. All three are idempotent (re-running skips
migrations already copied).

Nothing about this is otherwise cnfs-specific — it's the ordinary
engine-migration workflow, and it's the stable choice for released apps.

### Opt-in: in-place (read straight from the gems)

Uncomment the `CnfsSupport.migrations_paths[...]` line under a database (and
comment its hardcoded path) to have that database read migrations directly from
the gems — nothing copied. Each gem's paths are collected into
`CnfsSupport.migrations_paths` at boot, keyed by scope (`:tenant` → `db/migrate`,
`:global` → `db/global_migrate`, declared by `cnfs_tenanted`'s engine). A
migration added to any CNFS gem is then picked up on `bundle update` with no
re-copy, across every CNFS engine that ships migrations (e.g. `cnfs_okf`) at
once. Useful during rapid co-development across several gems and apps.

The presence of that ERB is the whole switch — there is no separate config flag.

> **In in-place mode, treat shipped tenant migrations as append-only and
> immutable across gem versions.** Because tenant databases are provisioned
> continuously and read migrations from the gem in place, editing an
> already-released tenant migration can put existing tenant databases out of
> sync with new ones. Add new migrations; never alter shipped ones.

---

## Notes & caveats

- **`tld_length = 0` is development-only.** It makes `acme.localhost` resolve as
  subdomain `acme`. Production subdomain resolution relies on real DNS and the
  default `tld_length`.
- **`cnfs_dev` is optional and not a dependency.** Multi-tenancy and the Pry
  console helpers are independent; the helpers simply activate if `cnfs_dev`
  happens to be present.

---

## Contributing

Bug reports and pull requests welcome.

## License

Available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).
