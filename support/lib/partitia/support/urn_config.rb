# frozen_string_literal: true

require_relative "config"

module Partitia
  module Support
    # The app's URN partition — the first segment of every URN any engine mints
    # (urn:<partition>:<service>:<region>:<account>:<resource_type>/<resource_id>),
    # our analog to AWS's `arn:aws`. One setting for the whole app, so every engine
    # that mints or resolves URNs agrees on it.
    #
    # A Partitia::Support::Config subclass: config/partitia_urn.yml →
    # credentials.partitia_urn → ENV["PARTITIA_URN_PARTITION"]. Set it before URNs
    # leave the app (policies, audit records, other systems): a URN minted under
    # one partition does not resolve under another.
    class UrnConfig < Config
      config_name :partitia_urn

      DEFAULT_PARTITION = "partitia"

      attr_config partition: DEFAULT_PARTITION

      class << self
        def partition
          instance.partition.to_s
        end
      end
    end
  end
end
