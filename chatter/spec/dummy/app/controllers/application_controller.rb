class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # The host's job: resolve the acting participant. Chatter's engine controllers
  # inherit from this controller (via Chatter.parent_controller) and pick this up.
  # We store a GlobalID so the same seam works for any participant type.
  def current_participant
    gid = session[:current_participant_gid]
    GlobalID::Locator.locate(gid) if gid
  end
  helper_method :current_participant
end
