# ⚠️  DEV/TEST SCAFFOLD — written by `rails g chatter:install:dev`.
# FAKE AUTH. "Become" any Person or Agent by storing its GlobalID in the session.
# There is NO password, NO real authentication — anyone can become anyone. This is
# a development convenience for exercising chatter's real-time delivery across
# browser tabs. NEVER ship this. In a real host, current_participant comes from
# your actual authentication system. Safe to delete when done.
class SessionController < ApplicationController
  def update
    participant = GlobalID::Locator.locate(params[:gid])
    session[:current_participant_gid] = participant&.to_gid&.to_s
    redirect_back fallback_location: chatter.root_path
  end
end
