require "securerandom"

module CnfsCognito
  # The broker's only controller (Plan 003 WS3). Its entire IAM knowledge is the
  # identity_resolver slot and the opaque principal.id — it never touches
  # identity storage.
  class SessionsController < ApplicationController
    SESSION_STASH = :cnfs_cognito_flow

    # GET /login — start the auth-code + PKCE flow: stash state/nonce/verifier
    # (and an optional bootstrap/invite link_token), then redirect to the IdP.
    def new
      instrument(:login_start, has_link_token: params[:link_token].present?) do
        logger.debug { "login start: link_token=#{params[:link_token].present?}" }
        state = SecureRandom.urlsafe_base64(32)
        nonce = SecureRandom.urlsafe_base64(32)
        verifier = CnfsCognito::Pkce.verifier

        session[SESSION_STASH] = {
          "state" => state,
          "nonce" => nonce,
          "code_verifier" => verifier,
          "link_token" => params[:link_token].presence
        }

        # The URL carries state/nonce/challenge — log the fact, never the URL.
        logger.debug { "redirecting to provider authorization endpoint" }
        redirect_to(
          CnfsCognito.provider.authorization_url(
            redirect_uri: callback_url,
            state: state,
            nonce: nonce,
            code_challenge: CnfsCognito::Pkce.challenge(verifier)
          ),
          allow_other_host: true
        )
      end
    end

    # GET /callback — validate state, exchange the code, verify the ID token,
    # resolve to a principal under the request's policy, establish the session.
    def callback
      # The critical span: the whole login latency (code exchange, token verify,
      # identity resolution, session establishment) plus the exact failure reason
      # via `outcome`. Failures here are expected security outcomes, so they are
      # recorded on the payload rather than left to error the span.
      instrument(:callback) do |event|
        logger.debug { "callback received" }
        stash = session.delete(SESSION_STASH) || {}
        unless valid_state?(stash)
          event[:outcome] = "invalid_state"
          logger.warn { "callback: state mismatch — rejecting" }
          next fail_flow("invalid_state")
        end

        begin
          tokens = CnfsCognito.provider.exchange_code(
            code: params[:code],
            redirect_uri: callback_url,
            code_verifier: stash["code_verifier"]
          )
          assertion = CnfsCognito.provider.verify(id_token: tokens["id_token"], nonce: stash["nonce"])
        rescue CnfsCognito::Providers::VerificationError
          # Never leak claim contents or provider internals into the user-facing error.
          event[:outcome] = "verification_failed"
          logger.warn { "callback: id-token verification failed" }
          next fail_flow("verification_failed")
        end

        policy = CnfsCognito.policy_resolver.call(request)
        event[:policy] = policy.to_s
        logger.debug { "resolving identity, policy=#{policy}" }
        result = CnfsCognito.identity_resolver.call(assertion, policy, stash["link_token"])

        if result.success?
          event[:outcome] = "success"
          establish_session(result.principal.id)
          logger.info { "sign-in ok: principal id=#{result.principal.id}" }
          redirect_to configured_path(CnfsCognito.after_sign_in_path), allow_other_host: false
        else
          event[:outcome] = result.failure_reason.to_s
          logger.warn { "sign-in failed: #{result.failure_reason}" }
          fail_flow(result.failure_reason)
        end
      end
    end

    # DELETE /logout — drop the session principal and land on the sign-out path.
    # (IdP-side single-logout is out of scope for this plan.)
    def destroy
      instrument(:logout) do
        session.delete(CnfsCognito.session_key)
        logger.info { "sign-out: cleared session" }
        redirect_to configured_path(CnfsCognito.after_sign_out_path), allow_other_host: false
      end
    end

    private

    def valid_state?(stash)
      params[:state].present? &&
        stash["state"].present? &&
        ActiveSupport::SecurityUtils.secure_compare(params[:state].to_s, stash["state"].to_s)
    end

    def establish_session(principal_id)
      reset_session
      session[CnfsCognito.session_key] = principal_id
    end

    def fail_flow(reason)
      flash[:alert] = I18n.t(
        "cnfs_cognito.sessions.failures.#{reason}",
        default: I18n.t("cnfs_cognito.sessions.failures.default")
      )
      redirect_to configured_path(CnfsCognito.after_sign_out_path), allow_other_host: false
    end

    # after_sign_in_path / after_sign_out_path may be a string or a callable
    # evaluated in controller context.
    def configured_path(path)
      path.respond_to?(:call) ? instance_exec(&path) : path
    end
  end
end
