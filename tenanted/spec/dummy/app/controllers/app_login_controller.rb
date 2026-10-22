# The public /app login entry point. Records the JIT policy intent in the
# session (the broker reads it at callback time via policy_resolver) and hands
# off to the broker's login, preserving any invite/bootstrap link_token.
class AppLoginController < ApplicationController
  def create
    session[:oidc_policy] = "jit"
    redirect_to cnfs_cognito.login_path(link_token: params[:link_token]), allow_other_host: false
  end
end
