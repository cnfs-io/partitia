# An operator route proving that resolved identity feeds authorization
# fail-closed (Plan 004 WS1.4). Runs behind TenantResolution (inherited from
# ApplicationController), Iam::Authenticatable, and Pundit's verify_authorized.
class DashboardController < ApplicationController
  include Iam::Authenticatable
  include Pundit::Authorization

  before_action :require_authentication
  after_action :verify_authorized

  def show
    authorize :dashboard, :show?
    render plain: "dashboard: #{current_user.id}"
  end

  # Pundit resolves policies against the canonical principal (never an IdP id).
  def pundit_user
    current_user
  end
end
