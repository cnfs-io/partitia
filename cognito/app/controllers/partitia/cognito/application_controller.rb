require "cnfs_support/instrumentable"
require "cnfs_support/logging"

module CnfsCognito
  # Base controller for the broker's own controllers. Deliberately inherits from
  # ActionController::Base (not the host's ApplicationController) so the broker
  # stays decoupled from the host application.
  #
  # Includes the CNFS instrumentation + logging mixins so every broker controller
  # gets `instrument` (emitting cnfs_cognito.<controller>.<verb> notifications)
  # and a `logger` tagged `cnfs_cognito`. These are concrete controllers in the
  # gem, so component_tag derives "cnfs_cognito" from the class name directly.
  class ApplicationController < ActionController::Base
    include CnfsSupport::Instrumentable
    include CnfsSupport::Logging
  end
end
