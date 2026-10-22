require "partitia/support"

module Partitia
  module Cognito
    # The auth-broker engine (ADR 0001 / Plan 003). Isolated namespace: routes and
    # controllers live under Partitia::Cognito and mount into a host at a chosen path
    # (the dummy mounts at /auth). The broker stores no identities and owns no
    # tables — it runs OIDC flows and hands verified assertions to a configured
    # identity resolver slot.
    class Engine < ::Rails::Engine
      isolate_namespace Partitia::Cognito

      # Every engine registers (ARCHITECTURE §3, Q6). The broker has no tables or
      # Tailwind-scanned views today; registering keeps it in the registry walk
      # so anything it adds later reaches the host with no extra wiring.
      Partitia::Support.plugins << self
    end
  end
end
