module CnfsCognito
  module Providers
    # Authentik (self-hosted) is the first provider. Its OIDC issuer lives at a
    # per-application path (…/application/o/<slug>/); generic OIDC discovery and
    # verification cover everything it needs, so this subclass is intentionally
    # (almost) empty. Its existence keeps the registry honest — nothing outside
    # the provider knows which IdP is configured — and gives Authentik-specific
    # quirks a home if any surface later.
    class Authentik < Oidc
    end
  end
end
