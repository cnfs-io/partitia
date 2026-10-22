# partitia-cognito

`Partitia::Cognito`: the OIDC sign-in broker. An isolated engine that runs the
authorization-code flow (PKCE, RS256-pinned ID-token verification) against a
registry of providers (Authentik first), and hands the verified assertion to a
host-wired `identity_resolver` (partitia-iam's `Resolution`, ADR 0004). It stores
no identities and owns no tables. Its controllers are isolated from the host's
`ApplicationController` on purpose: the broker must run before the host has a
principal.

Needs the pcm service `authentik` (`spec.metadata["partitia.services"]`).

## Install

```ruby
gem "partitia-cognito"
```

```sh
bin/rails generate partitia:cognito:install            # --mount-path /auth --app-slug <slug>
pcm up authentik                                       # http://localhost:9000
```

The generator is idempotent (a second run changes nothing and asks nothing):

| Writes | When |
|---|---|
| `mount Partitia::Cognito::Engine => "/auth"` in `config/routes.rb` | not already mounted |
| `config/initializers/partitia_cognito.rb`: provider, `identity_resolver`, `policy_resolver` | absent |
| `config/partitia_cognito.yml`: issuer, client_id, scopes per environment | absent |
| `:code, :state` in `config/initializers/filter_parameter_logging.rb` | not already filtered (file created if missing) |

## Entry points

Under the mount (default `/auth`):

| Route | |
|---|---|
| `GET /auth/login` | start sign-in (optional `link_token` for invites) |
| `GET /auth/callback` | the OIDC redirect URI to register in the IdP |
| `DELETE /auth/logout` | sign out |

## Configuration

`Partitia::Cognito::Config` (`config_name :partitia_cognito`): `issuer`,
`client_id`, `client_secret`, `scopes` (default `openid email profile`), each from
`config/partitia_cognito.yml`, then `credentials.partitia_cognito`, then
`PARTITIA_COGNITO_*`.

The generated yml points development at pcm's Authentik, with the app name as
the Authentik application slug and client ID:

```yaml
development:
  issuer: http://localhost:9000/application/o/<app-slug>/
  client_id: <app-slug>
  scopes: [openid, email, profile]
test:        # stubs; specs use WebMock
  issuer: http://authentik.test/application/o/<app-slug>/
  client_id: test-client-id
production:  # issuer and client_id from PARTITIA_COGNITO_* or credentials
```

`client_secret` is a secret: `bin/rails credentials:edit` (`partitia_cognito:
client_secret:`) or `PARTITIA_COGNITO_CLIENT_SECRET`. Never in the yml.

In Authentik, create an OAuth2/OpenID provider (confidential client, RS256 signing
key, scopes openid/email/profile) and an application with slug `<app-slug>`;
client ID `<app-slug>`; redirect URI `http://localhost:3000/auth/callback`.

Module slots (callables, not config): `identity_resolver` and `provider` raise
`ConfigurationError` when unset; `policy_resolver` defaults to `:invite_only`;
`session_key`, `after_sign_in_path`, `after_sign_out_path`.

## With partitia-iam

The generated initializer wires `identity_resolver` to
`Partitia::Iam::Resolution.resolve` (resolved lazily; neither gem requires the
other). `session_key` must match iam's (both default `:partitia_iam_user_id`).

## With partitia-tenanted

The callback has to run in the tenant's database: put tenanted's Rack resolver in
front of the mount (see `tenanted/spec/dummy/config/initializers/identity.rb`).

## Development

```sh
bundle exec rspec        # IdP stubbed with WebMock; no network, no container
bin/rubocop
```

The live discovery spec runs against pcm's Authentik and is skipped otherwise:

```sh
pcm up authentik
AUTHENTIK_ISSUER=http://localhost:9000/application/o/<slug>/ bundle exec rspec spec/integration
```

The dummy (`spec/dummy`, DB-less) mounts the engine at `/auth`.

## License

MIT.
