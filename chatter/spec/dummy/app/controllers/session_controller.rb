# Fake auth for the dummy: "become" any Person or Agent by storing its GlobalID
# in the session. This lives in the host, never in the engine.
class SessionController < ApplicationController
  def update
    participant = GlobalID::Locator.locate(params[:gid])
    session[:current_participant_gid] = participant&.to_gid&.to_s
    redirect_back fallback_location: chatter.root_path
  end
end
