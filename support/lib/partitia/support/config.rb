# frozen_string_literal: true

require "anyway_config"
require "active_support/core_ext/module/delegation"

module CnfsSupport
  # Base class for config classes across the CNFS gem family (anyway_config
  # convention). A gem defines a subclass per config surface:
  #
  #   module Iam
  #     class Config < CnfsSupport::Config
  #       config_name :iam    # config/iam.yml, credentials.iam, ENV["IAM_*"]
  #       attr_config :issuer, session_ttl: 3600
  #     end
  #   end
  #
  # Each subclass resolves values from, in ascending priority:
  #   1. config/<name>.yml (per-environment, ERB allowed)
  #   2. Rails credentials (under the config's name key) — when Rails is present
  #   3. ENV vars prefixed with <NAME>_ (nested keys via double underscore)
  #
  # Works pre-boot and without Rails, consistent with cnfs_support's charter:
  # anyway_config's Rails integrations (credentials source, config/configs
  # autoloading) activate only when Rails is loaded.
  class Config < Anyway::Config
    class << self
      # Singleton instance + delegation so `Iam::Config.issuer` works without
      # instantiating everywhere. (Same pattern anyway_config's install
      # generator produces — beware attribute names that shadow Anyway::Config
      # class methods, see palkan/anyway_config#120.)
      #
      # @instance is a class-level ivar, so each subclass memoizes its own.
      def instance
        @instance ||= new
      end

      # Drop the memoized instance (next access re-resolves all sources).
      # Primarily for specs that mutate ENV between examples.
      def reset_instance!
        @instance = nil
      end

      delegate_missing_to :instance
    end
  end
end
