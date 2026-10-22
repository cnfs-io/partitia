module Chatter
  class ApplicationController < Chatter.parent_controller.constantize
    helper_method :current_participant

    private

    # The host is expected to provide `current_participant` on the parent
    # controller. When it does, `super` resolves to it; when it doesn't (e.g. the
    # standalone ActionController::Base default), we raise a guiding error rather
    # than silently returning nil. Defining the method here (instead of relying on
    # pure inheritance) keeps the contract discoverable in the engine.
    def current_participant
      defined?(super) ? super : raise(NotImplementedError,
        "The host app must provide `current_participant` returning a Chatter participant. " \
        "Set Chatter.parent_controller to your host's base controller (which defines it), " \
        "or define current_participant in this controller.")
    end
  end
end
