class ApplicationController < ActionController::Base
  # No forgery protection needed for the broker's GET-driven OIDC redirects in
  # the dummy; request specs exercise the flow directly.
  allow_browser versions: :modern
end
