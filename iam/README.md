# Partitia::Iam
Short description and motivation.

## Usage
How to use my plugin.

## Installation
Add this line to your application's Gemfile:

```ruby
gem "partitia-iam"
```

And then execute:
```bash
$ bundle
```

Or install it yourself as:
```bash
$ gem install iam
```

## Integrations

iam requires neither sibling. Each integration is wired from the other side, or
switched on by `defined?(Partitia::Tenanted)`.

### With partitia-cognito

cognito verifies the IdP's ID token and hands the assertion to its
`Partitia::Cognito.identity_resolver` slot. cognito's installer wires that slot,
in `config/initializers/partitia_cognito.rb`, to:

```ruby
Partitia::Cognito.identity_resolver = ->(assertion, policy, link_token) {
  Partitia::Iam::Resolution.resolve(assertion:, policy:, link_token:)
}
```

`Resolution.resolve` maps `(issuer, subject)` to a principal through
`IdentityLink`, under the policy cognito's `policy_resolver` picks for the request:

- `:jit`: a known identity returns its principal; an unknown one gets a new
  `HumanPrincipal` and link on the spot.
- `:invite_only` (cognito's default): a known identity returns its principal; an
  unknown one needs a valid `link_token` (passed as `/auth/login?link_token=…`),
  which binds it to the pre-seeded principal and is consumed. Otherwise the
  result fails with `unknown_identity` or `invalid_link_token`.
- Any other policy fails with `invalid_policy`.

On success cognito stores `principal.id` under its `session_key`;
`Partitia::Iam::Authenticatable` reads it back as `current_user`. Both default to
`:partitia_iam_user_id`, so change both or neither. Resolution has no tenancy
logic: it runs in whatever database is already selected.

### First sign-in: claiming root

Every database has one root principal (ADR 0004), and cognito's policy fails closed
(`:invite_only`): nobody signs in until an identity is linked. The first one is root,
claimed with its bootstrap link token:

```sh
bin/rails partitia:iam:bootstrap                 # single-tenant (OWNER_EMAIL=… for root's email)
bin/rails partitia:iam:bootstrap TENANT=acme     # with partitia-tenanted (TENANT=platform too)
```

It prints `ROOT=unclaimed` and `LINK_TOKEN=<token>`, or `ROOT=claimed`. Sign in once
at `/auth/login?link_token=<token>` (cognito's mount): `Resolution` binds the IdP
identity you use to root and consumes the token. From then on root signs in with no
token. Each run while unclaimed issues a new token (single use, 7 days) and the old
one stops working; a database with no root yet (a single-tenant app) is seeded first
with the Account and root, as tenants are. A locked-out root:
`Partitia::Iam::RootRecovery.reset!` in its database. The service behind it is
`Partitia::Iam::Bootstrap`.

### With partitia-tenanted

When partitia-tenanted is loaded, iam's engine appends `TenantSeeder` to
`Partitia::Tenanted.after_provision`. Each provisioning run then seeds, inside the
new database, the `Account` singleton (named for the tenant) and a root
`HumanPrincipal` for the context's `owner_email`, and issues that root a bootstrap
link token (`Partitia::Iam::TenantSeeder.last_bootstrap_token`). The root redeems
the token with an `:invite_only` sign-in. This runs for
`Partitia::Tenanted::Tenant.create!` (each tenant database) and for
`Partitia::Tenanted.provision_platform!(owner_email:)` (the reserved platform
database). If seeding raises, provisioning is aborted and the tenant is not created.

Under tenancy the account handle in URNs and access-key IDs is the current
tenant's handle (`Partitia::Iam.current_account_handle`), unless the host pins
`account_handle`. A sign-in on a tenant's subdomain has to run in that tenant's
database, so the tenant must be selected at the Rack layer before cognito's
callback; see `tenanted/spec/dummy/config/initializers/identity.rb`.

## Contributing
Contribution directions go here.

## License
The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
