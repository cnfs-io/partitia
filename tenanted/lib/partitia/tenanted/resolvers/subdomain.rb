require "cnfs_tenanted/resolvers/base"

module CnfsTenanted
  module Resolvers
    # Tenant from the request subdomain. The default and most common strategy.
    #
    #     acme.example.com        -> "acme"
    #     www.example.com         -> nil   (excluded)
    #     example.com             -> nil   (no subdomain)
    #     203.0.113.5             -> nil   (IP host, never a tenant)
    #     acme.staging.example.com -> "acme" (leftmost label by default)
    #
    # Ported from Apartment's Subdomain/FirstSubdomain elevators, with two
    # improvements folded in:
    #
    #   * PublicSuffix-based parsing (when the gem is loadable) so multi-part
    #     and international TLDs resolve correctly (e.g. acme.example.co.uk ->
    #     "acme", not "example"). Apartment depends on public_suffix hard; we
    #     treat it as a soft enhancement and fall back to a leftmost-label
    #     parse so the resolver still works in a lean app without it.
    #   * IP-address hosts are rejected — an IP is never a tenant subdomain.
    #
    # Options:
    #   excluded: subdomains that should resolve to nil (run untenanted).
    #             Defaults to %w[www]. Useful for reserved names like
    #             "www", "admin", "api".
    #   first_label_only: for nested subdomains, take only the leftmost label
    #             (acme.staging -> "acme"). Default true, matching the common
    #             "tenant is always the leftmost label" convention. Set false
    #             to use the full subdomain string (acme.staging -> "acme.staging").
    class Subdomain < Base
      DEFAULT_EXCLUDED = %w[www].freeze

      def initialize(excluded: DEFAULT_EXCLUDED, first_label_only: true)
        @excluded = Array(excluded).map(&:to_s).freeze
        @first_label_only = first_label_only
      end

      def call(request)
        sub = extract_subdomain(request)
        return nil if sub.nil?

        sub = sub.split(".").first if @first_label_only
        return nil if @excluded.include?(sub)

        present_or_nil(sub)
      end

      private

      # Returns the subdomain portion of the host, or nil. Prefers PublicSuffix
      # for correct TLD handling; degrades to a host-minus-registered-domain
      # heuristic, and finally to ActionDispatch's own #subdomain.
      def extract_subdomain(request)
        host = request.host.to_s
        return nil if host.empty? || ip_host?(host)

        if public_suffix_available?
          parsed = PublicSuffix.parse(host, ignore_private: true)
          present_or_nil(parsed.trd) # trd = "transit registrable domain" == subdomain(s)
        else
          fallback_subdomain(request, host)
        end
      rescue PublicSuffix::Error
        # Any parse failure on a non-public host (e.g. *.localhost in dev, or a
        # made-up internal TLD) — PublicSuffix::Error is the base class for
        # DomainInvalid/DomainNotAllowed and friends. Fall back so local
        # development still resolves tenants without a real TLD.
        fallback_subdomain(request, host)
      end

      # Without PublicSuffix, lean on ActionDispatch's #subdomain when present
      # (host apps configure tld_length for *.localhost — see development.rb),
      # otherwise treat everything left of the last two labels as the subdomain.
      def fallback_subdomain(request, host)
        if request.respond_to?(:subdomain)
          ad = request.subdomain.to_s
          return present_or_nil(ad) unless ad.empty?
        end

        labels = host.split(".")
        return nil if labels.length <= 2

        present_or_nil(labels[0...-2].join("."))
      end

      def ip_host?(host)
        !/\A\d{1,3}(?:\.\d{1,3}){3}\z/.match(host).nil? || host.include?(":") # IPv4 or IPv6
      end

      def public_suffix_available?
        return @public_suffix_available if defined?(@public_suffix_available)

        @public_suffix_available =
          begin
            require "public_suffix"
            true
          rescue LoadError
            false
          end
      end
    end
  end
end
