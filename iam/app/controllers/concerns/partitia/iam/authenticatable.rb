module Partitia
  module Iam
    # Controller concern that resolves the canonical principal from the session
    # each request and exposes it as `current_user` / `Partitia::Iam::Current.user`
    # (ADR 0004). The session carries the canonical user id (never an IdP subject);
    # the broker (partitia-cognito) writes it after a successful resolution. This is
    # the substrate Pundit wiring builds on (deferred to Plan 004).
    #
    # Machine requests do not use this path — they authenticate directly via
    # Partitia::Iam::Credential.authenticate (ADR 0002).
    module Authenticatable
      extend ActiveSupport::Concern

      included do
        before_action :resolve_current_user
        helper_method :current_user if respond_to?(:helper_method)
      end

      private

      # A stale/absent session id resolves to nil — treated as anonymous, never an
      # error. No id, no query: an anonymous request touches no database (under
      # partitia-tenanted the apex has no identity plane to query).
      def resolve_current_user
        instrument_iam(:authenticate_request) do |event|
          principal_id = session[Partitia::Iam.config.session_key]
          Partitia::Iam::Current.user = principal_id.presence && Partitia::Iam::Principal.find_by(id: principal_id)
          event[:authenticated] = !Partitia::Iam::Current.user.nil?
          # Mirror the span's boolean for now-visibility. Never the session id.
          partitia_iam_logger.debug { "resolve_current_user: authenticated=#{event[:authenticated]}" }
        end
      end

      def current_user
        Partitia::Iam::Current.user
      end

      # Halt anonymous requests. 401 by default; a host that wants a login
      # redirect overrides this (the engine has no login route of its own — that
      # is the broker's surface).
      def require_authentication
        instrument_iam(:authz_gate) do |event|
          if current_user
            event[:outcome] = "allowed"
            partitia_iam_logger.debug { "authz gate: allowed" }
          else
            event[:outcome] = "denied"
            partitia_iam_logger.warn { "authz gate: denied (anonymous)" }
            render plain: I18n.t("partitia_iam.authentication.required"), status: :unauthorized
          end
        end
      end

      # Emit under the gem's own component (iam.authenticatable.*) rather than the
      # host's ApplicationController: this is a mixin, so `self` is the host
      # controller and Partitia::Support::Instrumentable#instrument would compose the
      # event from the wrong class. `Authenticatable.name` resolves lexically to
      # Partitia::Iam::Authenticatable, keeping the component "iam".
      def instrument_iam(verb, **payload, &block)
        name = Partitia::Support::Instrumentable.event_name(Authenticatable.name, verb)
        ActiveSupport::Notifications.instrument(name, **payload, &block)
      end

      # A logger tagged for iam's own component, not the host controller's. Inside
      # this mixin `self` is the host controller, so the default `logger`'s tag
      # would be the host app's; build from Authenticatable.name (→ partitia_iam) so
      # iam's lines group under partitia_iam regardless of which app hosts the concern
      # — the same reason instrument_iam pins the event name.
      def partitia_iam_logger
        @partitia_iam_logger ||= Partitia::Support::Logging.build_for(Authenticatable.name)
      end
    end
  end
end
