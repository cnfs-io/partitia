# cnfs_tenanted — progress

Append-only completion entries, one per plan (see `~/spikes/chorus/doc`).

---

## Plan 001 — Global plane, reserved tenant, hooks (2026-07-05)

Shaped `cnfs_tenanted` into the ADR 0003 gem. **`bundle exec rspec` → 52 examples,
0 failures; `bundle exec rubocop` → clean.** Six workstreams:

### What shipped

- **WS1 — Removed the per-tenant `Account`** (ownership rule, ADR 0003 §6). Deleted
  the model, controller, views, `create_accounts` migration, and the install
  generator's `accounts_controller` template + reference. `Tenant` no longer
  seeds an Account; the per-database singleton is `Iam::Account`, owned by iam.
- **WS2 — Renamed `Tenancy*` → `TenantNotFound*`.** Controller, view dir, route
  target, and generator template. Kept the `tenant-unknown` path, the
  `tenant_unknown` helper, and `#unknown` semantics.
- **WS3 — Immutable handle as the routing key** (ADR 0002 §1/§5). `Tenant` gained
  `handle` (Crockford-ish base32, `a–z` minus `i/l/o/u` plus `2–9`, length 8,
  generated before validation, unique, immutable via an on-update guard) and
  `owner_email` (null-false). The `create_tenants` migration was edited **in
  place** (pre-v1 rule). Databases are keyed by `handle`; `subdomain` is the
  mutable lookup. `TenantResolution` now does subdomain → `Tenant` lookup →
  `with_tenant(handle)`. `Resolvers.default` excludes the reserved handle.
- **WS4 — `after_provision` hook registry.** `CnfsTenanted.after_provision` is an
  ordered callable list; each hook receives a **provisioning context** (`#name`
  + `#owner_email`) and runs inside `with_tenant(handle)` on the fresh DB.
  `Tenant#after_create` delegates to `CnfsTenanted.run_provision`.
- **WS5 — Reserved tenant + platform entry point + console guard.**
  `RESERVED_HANDLE = "platform"`; `provision_platform!(owner_email:)` (idempotent,
  runs the same registry with a `PlatformContext`); `with_platform` (pins the
  reserved context + installs the scope guard); `each_tenant`/`tenant_handles`
  (reserved excluded); `platform_console_guard` (default-deny) applied as a
  `before_action` on `TenantsController`.
- **WS6 — Specs** (52 examples) + dummy wired for real tenanted operation.

### Decisions worth flagging

- **Cross-gem friction — the activerecord-tenanted `TenantSelector` middleware.**
  a-r-tenanted auto-inserts a Rack middleware that, by default, resolves a
  tenant by **raw subdomain** and switches to a DB of that name. That is
  incompatible with handle-keyed DBs (subdomain → handle needs a `Tenant`
  lookup a pure request resolver can't do). Resolution: the engine now sets
  `config.active_record_tenanted.tenant_resolver = ->(_){ nil }` so the
  middleware runs every request untenanted and defers to
  `CnfsTenanted::TenantResolution` (the concern owns the subdomain→handle lookup
  and the richer not-found seam). This is a gem-level change affecting all
  hosts. *Feedback for the doc set:* WS3.4 described the concern but not the
  middleware neutralization it requires — worth folding into ADR 0003 §5 or the
  plan.
- **Platform scope-guard mechanism (WS5.3).** A `sql.active_record`
  `ActiveSupport::Notifications` subscriber scoped to the `with_platform` block,
  parsing the table name from each query and raising `PlatformScopeViolation`
  for anything outside `platform_table_prefixes` (default `%w[iam_]`) + AR
  internals. It is a **tripwire, not a transactional gate**: `sql.active_record`
  fires *after* execution, so a violating write reaches the reserved DB before
  the guard raises. Acceptable pre-v1 (no app-model writes should occur in the
  platform context; the guard turns a mistake into a loud, fast failure).
  Raising from the subscriber propagates cleanly as `PlatformScopeViolation` on
  this Rails (8.1) — no `InstrumentationSubscriberError` wrapping observed.
  Simplification vs the plan: the subscriber is not filtered by connection
  (fine for current specs; revisit if global-DB queries ever run inside the
  block).
- **after_provision failure-cleanup decision (WS4/WS6).** On a hook raise during
  **tenant** provisioning, `run_provision` drops the freshly created tenant DB
  (`cleanup_on_failure: true`) and re-raises; the re-raise rolls back the
  `after_create` transaction, so neither the `Tenant` row nor an orphan DB
  survives (proven by spec). For the **platform** run, `provision_platform!`
  uses `cleanup_on_failure: false` and its idempotence guard is DB-file
  existence: a half-seeded reserved DB (crash mid-hook) is recovered by deleting
  `storage/<env>/platform.sqlite3` and re-running (pre-v1; noted in the method).
- **Dummy wiring added (WS6).** `spec/dummy` gained host controllers
  (`Tenants`, `TenantNotFound`, plus `Probe`/`ProbeOverride` for resolution
  specs), `include CnfsTenanted::TenantResolution` in its `ApplicationController`,
  and probe routes. The stale committed `db/schema.rb` (which Rails loads in
  preference to migrations) had to be deleted and regenerated so the new
  `handle`/`owner_email` columns landed — a reminder that in-place migration
  edits require dropping the schema dump. The dummy's generated schema dumps are
  now rubocop-excluded.

### How to run

```
cd ~/spikes/chorus/tenanted
bundle exec rspec        # 52 examples
bundle exec rubocop      # clean
```

Test DBs are managed by `spec/support/tenancy.rb` (per-example genesis/teardown,
since RSpec doesn't get a-r-tenanted's Minitest integration). If the schema ever
drifts after an in-place migration edit: `rm spec/dummy/db/schema.rb` then
`RAILS_ENV=test bin/rails db:drop db:create db:migrate` from `spec/dummy`.

---

## Plan 004 — Integration: three gems, one dummy, end-to-end (2026-07-05)

Wired `iam` + `cnfs_cognito` into this gem's `spec/dummy` and proved the whole
architecture with request-level specs. **`bundle exec rspec` → 67 examples, 0
failures** (52 from Plan 001 + 15 integration), stable across seeds; RuboCop
clean. **iam's own suite untouched — still 78 green** (the single-tenant
regression guard).

### What shipped

- **Dummy-only sibling gems.** `iam` and `cnfs_cognito` added to the **Gemfile**
  (never the gemspec — cnfs_tenanted depends on neither). iam's `db/migrate`
  joins the tenant scope via the CnfsSupport registry, so every tenant DB
  (reserved included) carries `iam_*` tables; the global DB carries only
  `tenants` (asserted). iam's `TenantSeeder` auto-registers into
  `after_provision` (its engine's guarded `after_initialize`).
- **`config/initializers/identity.rb`** — the canonical host wiring, and the
  reference for how a host composes the three gems: broker→IAM
  `identity_resolver`, route-based `policy_resolver`, the reserved-DB
  `platform_console_guard`, `after_sign_in/out_path`, provider registration, and
  the Rack tenant resolver (below).
- **Dummy MVC.** Mounted the broker at `/auth`; `/dashboard` (operator route:
  `Iam::Authenticatable` + `require_authentication` + one `DashboardPolicy` with
  `verify_authorized`, fail-closed); `/app/login` (JIT entry) and
  `/platform/login` (reserved-DB entry). Test setup provisions the platform DB
  and seeds an App Admin explicitly.
- **Specs (WS2, all nine scenarios).** Provisioning + seed; root bootstrap
  (invite+token, replay rejected); invite-only-no-token; end-user JIT
  (idempotent); tenant isolation; machine auth + embedded handle; root
  constraints + `RootRecovery`; platform console (deny anon / allow App Admin /
  provision through it) + scope guard; reserved-not-from-subdomain;
  unknown-subdomain seam; global-DB-has-no-identity-tables. The OIDC WebMock
  harness was **copied** from cnfs_cognito's specs (cross-gem `require` of a
  gem's spec-support path is brittle; copy noted here).

### Cross-gem friction discovered (fed back / flagged)

The inversion-slot architecture composed with **zero changes to iam or
cnfs_cognito** — every touchpoint was a host-configured slot. The friction was
all at the tenant-resolution layer:

1. **The broker's callback runs in a mounted engine, which the Plan 001
   concern-based tenant resolution does not cover.** Fix: re-point
   activerecord-tenanted's Rack `TenantSelector` at a subdomain→handle resolver
   (identity.rb), so tenant context is established at the Rack layer for host
   routes AND mounted engines (ADR 0001: DB selection precedes everything). This
   is set in `after_initialize` to win over Plan 001's engine-initializer
   neutralization. **Recommendation:** cnfs_tenanted should ship this
   handle-mapping resolver as a first-class option rather than leaving each host
   to write it — Plan 001's concern-only default doesn't cover mounted engines.
   (Done in the dummy since the a-r-tenanted resolver is a host-config point by
   design; flagged for promotion into the gem.)
2. **cnfs_cognito resolves policy at CALLBACK time**, when only the callback
   request is visible — so route-based policy (`/app` → `:jit`) can't read the
   originating path. The host carries the intent through the OIDC round-trip in
   the session (the `/app/login` entry sets it). Flag for cnfs_cognito: consider
   stashing a caller-supplied policy hint in `new`.
3. **The platform (App Admin) login authenticates as the platform** but the
   reserved DB is not subdomain-addressable (ADR 0003 §2). A `/platform/login`
   entry sets a session flag the Rack resolver reads to pin the reserved handle
   for that round-trip; the broker's `reset_session` clears it on success.
4. **Test-harness robustness (`spec/support/tenancy.rb`).** RSpec seeds the RNG,
   so Tenant handle generation is deterministic within a seed; combined with the
   FIXED reserved handle and activerecord-tenanted's LRU connection-pool cache,
   a stale/partial tenant DB file (or a pool bound to a deleted inode) would be
   silently reused and re-seeded ("already a root"). Cleanup now: destroy all
   listed tenants **plus the reserved handle explicitly**, physically delete
   per-tenant SQLite files, and `clear_all_connections!`, plus a `before(:suite)`
   purge. The stable-keypair note (below) is the OIDC analog.
5. **OIDC harness + singleton provider.** The broker's provider is a boot-time
   singleton that caches discovery/JWKS on first use, so the test signing key
   must be **stable across the suite** (the copied harness memoises one keypair
   at module level) or a later token fails signature verification against the
   cached JWKS.

### How to run it

```
cd ~/spikes/chorus/tenanted
bundle exec rspec        # 67 examples, 0 failures
bundle exec rubocop      # clean
# regression: iam's own suite stays green and single-tenant
( cd ../iam && bundle exec rspec )   # 78 examples, 0 failures
```
