require "cnfs_tenanted/resolvers/base"
require "cnfs_tenanted/resolvers/subdomain"
require "cnfs_tenanted/resolvers/host_hash"
require "cnfs_tenanted/resolvers/header"

module CnfsTenanted
  module Resolvers
    # The strategy used when nothing is configured: subdomain, excluding "www"
    # and the reserved platform handle (ADR 0003 §2 — the reserved tenant must
    # never resolve from a subdomain). Matches the behavior the TenantResolution
    # concern hardcoded historically, plus the reserved-handle exclusion.
    def self.default
      @default ||= Subdomain.new(excluded: %w[www] + [ CnfsTenanted::RESERVED_HANDLE ])
    end
  end
end
