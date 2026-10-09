module Iam
  # Controller concern that resolves the canonical principal from the session
  # each request and exposes it as `current_user` / `Iam::Current.user`
  # (ADR 0004). The session carries the canonical user id (never an IdP subject);
  # the broker (cnfs_cognito) writes it after a successful resolution. This is
  # the substrate Pundit wiring builds on (deferred to Plan 004).
  #
  # Machine requests do not use this path — they authenticate directly via
  # Iam::Credential.authenticate (ADR 0002).
  module Authenticatable
    extend ActiveSupport::Concern

    included do
      before_action :resolve_current_user
      helper_method :current_user if respond_to?(:helper_method)
    end

    private

    # A stale/absent session id resolves to nil — treated as anonymous, never an
    # error.
    def resolve_current_user
      instrument_iam(:authenticate_request) do |event|
        Iam::Current.user = Iam::Principal.find_by(id: session[Iam.config.session_key])
        event[:authenticated] = !Iam::Current.user.nil?
        # Mirror the span's boolean for now-visibility. Never the session id.
        iam_logger.debug { "resolve_current_user: authenticated=#{event[:authenticated]}" }
      end
    end

    def current_user
      Iam::Current.user
    end

    # Halt anonymous requests. 401 by default; a host that wants a login
    # redirect overrides this (the engine has no login route of its own — that
    # is the broker's surface).
    def require_authentication
      instrument_iam(:authz_gate) do |event|
        if current_user
          event[:outcome] = "allowed"
          iam_logger.debug { "authz gate: allowed" }
        else
          event[:outcome] = "denied"
          iam_logger.warn { "authz gate: denied (anonymous)" }
          render plain: I18n.t("iam.authentication.required"), status: :unauthorized
        end
      end
    end

    # Emit under the gem's own component (iam.authenticatable.*) rather than the
    # host's ApplicationController: this is a mixin, so `self` is the host
    # controller and CnfsSupport::Instrumentable#instrument would compose the
    # event from the wrong class. `Authenticatable.name` resolves lexically to
    # Iam::Authenticatable, keeping the component "iam".
    def instrument_iam(verb, **payload, &block)
      name = CnfsSupport::Instrumentable.event_name(Authenticatable.name, verb)
      ActiveSupport::Notifications.instrument(name, **payload, &block)
    end

    # A logger tagged for iam's own component, not the host controller's. Inside
    # this mixin `self` is the host controller, so the default `logger`'s tag
    # would be the host app's; build from Authenticatable.name (→ cnfs_iam) so
    # iam's lines group under cnfs_iam regardless of which app hosts the concern
    # — the same reason instrument_iam pins the event name.
    def iam_logger
      @iam_logger ||= CnfsSupport::Logging.build_for(Authenticatable.name)
    end
  end
end
