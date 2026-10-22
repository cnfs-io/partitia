require "partitia/support/instrumentable"
require "partitia/support/logging"

module Partitia
  module Cognito
    # Base controller for the broker's own controllers. Deliberately inherits from
    # ActionController::Base (not the host's ApplicationController) so the broker
    # stays decoupled from the host application.
    #
    # Includes the CNFS instrumentation + logging mixins so every broker controller
    # gets `instrument` (emitting partitia_cognito.<controller>.<verb> notifications)
    # and a `logger` tagged `partitia_cognito`. These are concrete controllers in the
    # gem, so component_tag derives "partitia_cognito" from the class name directly.
    class ApplicationController < ActionController::Base
      include Partitia::Support::Instrumentable
      include Partitia::Support::Logging
    end
  end
end
