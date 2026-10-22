require "partitia/tenanted/resolvers/base"
require "partitia/tenanted/resolvers/subdomain"
require "partitia/tenanted/resolvers/host_hash"
require "partitia/tenanted/resolvers/header"

module Partitia
  module Tenanted
    module Resolvers
      # The strategy used when nothing is configured: subdomain, excluding "www"
      # and the reserved platform handle (ADR 0003 §2 — the reserved tenant must
      # never resolve from a subdomain). Matches the behavior the TenantResolution
      # concern hardcoded historically, plus the reserved-handle exclusion.
      def self.default
        @default ||= Subdomain.new(excluded: %w[www] + [ Partitia::Tenanted::RESERVED_HANDLE ])
      end
    end
  end
end
