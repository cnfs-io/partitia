# The platform (App Admin) login entry point. Flags the session so the Rack
# tenant resolver pins the reserved database for the OIDC round-trip — the App
# Admin authenticates against the platform plane (ADR 0003 §2/§7). The flag is
# cleared by the broker's reset_session on success.
class PlatformLoginController < ApplicationController
  def create
    session[:platform_auth] = true
    redirect_to cnfs_cognito.login_path(link_token: params[:link_token]), allow_other_host: false
  end
end
