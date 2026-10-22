module Partitia
  module Cognito
    # The auth-broker engine (ADR 0001 / Plan 003). Isolated namespace: routes and
    # controllers live under Partitia::Cognito and mount into a host at a chosen path
    # (the dummy mounts at /auth). The broker stores no identities and owns no
    # tables — it runs OIDC flows and hands verified assertions to a configured
    # identity resolver slot.
    class Engine < ::Rails::Engine
      isolate_namespace Partitia::Cognito
    end
  end
end
