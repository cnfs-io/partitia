require "chatter/version"
require "chatter/engine"
require 'cnfs_support'

module Chatter
  # The host's base controller (a string, constantized at controller-load time).
  # It is expected to provide `current_participant`. Defaults to a safe standalone
  # base so the engine boots without a host; a real host sets this in an initializer
  # that runs before the engine's controllers load (the turbo-rails pattern).
  mattr_accessor :parent_controller, default: "ActionController::Base"

  # The engine can't enumerate host participant models (it never names them), but
  # the "start a conversation" UI needs candidates. The host supplies a callable
  # returning the participants the current user may talk to. Defaults to none.
  mattr_accessor :participant_candidates, default: -> { [] }
end
