require "cnfs_tenanted/resolvers/base"

module CnfsTenanted
  module Resolvers
    # Tenant from an explicit hostname -> tenant-name mapping.
    #
    #     CnfsTenanted::Resolvers::HostHash.new(
    #       "acme.com"        => "acme",
    #       "shop.widgets.io" => "widgets",
    #     )
    #
    # Ported from Apartment's HostHash elevator. The use case subdomain
    # resolution can't express: customers on their own vanity domains. A host
    # not in the map resolves to nil (run untenanted) — NOT an error.
    #
    # This differs deliberately from Apartment, which raises TenantNotFound on a
    # missing host. Here, resolvers only ever answer "which tenant?" and leave
    # existence/404 decisions to the caller; returning nil keeps that boundary
    # clean and lets an unmapped host fall through to the bare-domain surface.
    # If you want unmapped hosts to 404, compose this with a strict resolver or
    # let the caller treat a nil-from-a-known-vanity-host as not-found.
    #
    # Lookup is case-insensitive on the host and ignores a leading "www.".
    class HostHash < Base
      def initialize(map = {})
        @map = map.transform_keys { |k| normalize(k) }.freeze
      end

      def call(request)
        present_or_nil(@map[normalize(request.host)])
      end

      private

      def normalize(host)
        host.to_s.downcase.sub(/\Awww\./, "")
      end
    end
  end
end
