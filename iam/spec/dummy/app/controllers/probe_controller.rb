# Exercises Iam::Authenticatable for request specs. `sign_in` stands in for the
# broker writing the canonical id into the session after a successful
# resolution; `whoami` reports the resolved principal; `protected_area` is
# behind require_authentication.
class ProbeController < ApplicationController
  include Iam::Authenticatable

  before_action :require_authentication, only: :protected_area

  def whoami
    render plain: current_user ? "user:#{current_user.id}" : "anonymous"
  end

  def protected_area
    render plain: "ok"
  end

  # Test-only session writer (the real writer is cnfs_cognito's SessionsController).
  def sign_in
    session[Iam.config.session_key] = params[:id]
    head :ok
  end
end
