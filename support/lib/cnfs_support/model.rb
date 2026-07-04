require "active_support/concern"

require_relative "logging"
require_relative "instrumentable"

module CnfsSupport
  # The one concern a model includes to get the standard CNFS model behaviour.
  # Bundles the individual concerns so an ApplicationRecord (in a gem or an app)
  # opts in with a single line instead of tracking the full list:
  #
  #   class ApplicationRecord < ActiveRecord::Base
  #     include CnfsSupport::Model
  #   end
  #
  # Every model then has:
  #   - `logger`            tagged with the gem's component (CnfsSupport::Logging)
  #   - `instrument(verb)`  emitting standardized cnfs notifications
  #                         (CnfsSupport::Instrumentable)
  #
  # Both are lazy and cheap, so applying this to a base class touches every model
  # without imposing cost on models that never log or instrument. New shared
  # model concerns get added here once and every consumer picks them up.
  #
  # This is an ActiveSupport::Concern so the bundle can grow to use `included do`
  # / `class_methods do` blocks and dependency chaining without each consumer
  # changing. The bundled concerns use their own `included` hooks, which compose
  # correctly when included from here.
  module Model
    extend ActiveSupport::Concern

    include CnfsSupport::Logging
    include CnfsSupport::Instrumentable
  end
end
