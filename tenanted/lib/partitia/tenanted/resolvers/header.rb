require "partitia/tenanted/resolvers/base"

module Partitia
  module Tenanted
    module Resolvers
      # Tenant from an HTTP request header. For setups where tenant identity is
      # established at the edge (CloudFront, Nginx, an API gateway) and injected
      # as a header, or for APIs where clients name their tenant explicitly.
      #
      #     Partitia::Tenanted::Resolvers::Header.new                       # X-Tenant-Id
      #     Partitia::Tenanted::Resolvers::Header.new(header: "X-Acme-Org")
      #
      # Ported from Apartment's Header elevator.
      #
      # SECURITY: a request header is client-controllable unless something
      # trusted overwrites it at the edge. Only use this strategy when an edge
      # proxy you control sets (and strips any inbound copy of) the header —
      # otherwise any client can impersonate any tenant. The `trusted:` flag here
      # does not change behavior; it exists to document intent and to drive a
      # boot-time warning if you wire one up (as activerecord-tenanted/Apartment
      # do). Default false so the unsafe case is the one you have to opt into
      # consciously.
      class Header < Base
        attr_reader :header_name, :trusted

        def initialize(header: "X-Tenant-Id", trusted: false)
          # ActionDispatch/Rack expose headers as HTTP_X_TENANT_ID.
          @rack_key = "HTTP_#{header.to_s.upcase.tr('-', '_')}"
          @header_name = header.to_s.freeze
          @trusted = trusted
        end

        def call(request)
          present_or_nil(request.get_header(@rack_key))
        end
      end
    end
  end
end
