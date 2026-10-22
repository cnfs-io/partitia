module Iam
  # The broker↔IAM resolution contract (ADR 0004): turn a verified assertion
  # into a canonical principal under the applicable policy.
  #
  #   Iam::Resolution.resolve(assertion:, policy:, link_token: nil) -> Result
  #
  # ALWAYS runs inside an already-selected database context (a tenant DB, the
  # reserved DB, or the single-tenant DB) — the full identity coordinate is
  # (database, issuer, subject) and the database was chosen before resolution
  # began. This class contains NO tenancy awareness whatsoever.
  #
  # Placement: app/services (autoloaded as Iam::Resolution) — it is a stateless
  # domain service, not an Active Record model.
  class Resolution
    include CnfsSupport::Instrumentable
    include CnfsSupport::Logging

    # Plain-string failure vocabulary (never Rails enums).
    UNKNOWN_IDENTITY   = "unknown_identity".freeze
    INVALID_LINK_TOKEN = "invalid_link_token".freeze
    INVALID_POLICY     = "invalid_policy".freeze

    Result = Struct.new(:principal, :failure_reason, keyword_init: true) do
      def success?
        !principal.nil?
      end
    end

    # The identity-resolution span (iam.resolution.resolve): records the policy
    # and the outcome (success / the failure vocabulary above) so a login's IAM
    # verdict is visible in the trace without leaking assertion contents.
    def self.resolve(assertion:, policy:, link_token: nil)
      instrument(:resolve, policy: policy.to_s) do |event|
        result = new(Iam::Assertion.wrap(assertion), policy, link_token).resolve
        event[:outcome] = result.success? ? "success" : result.failure_reason
        result
      end
    end

    def initialize(assertion, policy, link_token)
      @assertion = assertion
      @policy = policy&.to_sym
      @link_token = link_token
    end

    def resolve
      logger.debug { "resolve: policy=#{@policy} link_token=#{!@link_token.nil?}" }
      case @policy
      when :jit          then resolve_jit
      when :invite_only  then resolve_invite_only
      else                    failure(INVALID_POLICY) # fail closed on absent/unknown policy
      end
    end

    private

    # End-users: known identity returns its principal; unknown creates a
    # HumanPrincipal + link on the spot.
    def resolve_jit
      link = find_link
      logger.debug { "resolve: existing link #{link ? 'found' : 'none, provisioning'}" }
      return success(link.principal) if link

      # First sighting of this identity: provision a principal + link on the spot.
      # A distinct span (iam.resolution.provision_jit) so JIT writes are separable
      # from the cheap known-identity path.
      principal = nil
      instrument(:provision_jit, issuer: @assertion.issuer) do
        ActiveRecord::Base.transaction do
          principal = Iam::HumanPrincipal.create!(name: @assertion.display_name, email: @assertion.email)
          create_link(principal)
        end
      end
      # After the create commits — id + issuer host only, never subject/email.
      logger.info { "jit provision: created principal id=#{principal.id} issuer=#{@assertion.issuer}" }
      success(principal)
    end

    # Operators/App Admins/root: known identity returns its principal; unknown
    # fails, UNLESS a valid link token identifies a pre-seeded principal — then
    # bind this assertion to it and consume the token.
    def resolve_invite_only
      link = find_link
      logger.debug { "resolve: existing link #{link ? 'found' : 'none'}" }
      return success(link.principal) if link
      return failure(UNKNOWN_IDENTITY) if @link_token.to_s.empty?

      principal = Iam::HumanPrincipal.find_by_link_token(@link_token)
      return failure(INVALID_LINK_TOKEN) unless principal

      ActiveRecord::Base.transaction do
        create_link(principal)
        principal.consume_link_token!
      end
      logger.info { "invite bind: principal id=#{principal.id} bound via link token" }
      success(principal)
    end

    def find_link
      Iam::IdentityLink.find_by(issuer: @assertion.issuer, subject: @assertion.subject)
    end

    def create_link(principal)
      principal.identity_links.create!(issuer: @assertion.issuer, subject: @assertion.subject).tap do
        # Emitted from the caller so the line reads in flow context. Issuer host
        # is fine to log; the subject (IdP sub) is not.
        logger.info { "identity link bound: principal id=#{principal.id} issuer=#{@assertion.issuer}" }
      end
    end

    def success(principal)
      Result.new(principal: principal)
    end

    def failure(reason)
      # Single choke point so no failure branch is missed; keyed by the same
      # vocabulary the span's outcome uses.
      logger.warn { "resolve failed: #{reason}" }
      Result.new(failure_reason: reason)
    end
  end
end
