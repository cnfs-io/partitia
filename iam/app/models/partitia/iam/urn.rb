module Partitia
  module Iam
    # URN grammar value object (ADR 0002 §4) — our analog to an AWS ARN:
    #
    #   urn:<partition>:iam:<region>:<account>:<resource_type>/<resource_id>
    #   e.g. urn:partitia:iam::a7f3k2xy:user/alice
    #
    # - partition — the app's, from Partitia::Support::UrnConfig (default "partitia"; ADR 0007)
    # - iam       — fixed service namespace for this engine
    # - region    — empty for IAM, mirroring AWS's global IAM service
    # - account   — the account handle (ADR 0002 §1); real from day one (§2)
    # - resource_type / resource_id — per model (resource_id via overridable urn_id)
    #
    # Pure builder/parser; no persistence knowledge. The Partitia::Iam::HasUrn concern wires
    # it onto models (to_urn / find_by_urn / urn_id).
    module Urn
      SERVICE = "iam".freeze

      Parsed = Data.define(:partition, :service, :region, :account, :resource_type, :resource_id) do
        def valid? = service == SERVICE && !resource_type.to_s.empty? && !resource_id.to_s.empty?
      end

      module_function

      def build(account:, resource_type:, resource_id:, partition: Partitia::Support::UrnConfig.partition, region: Partitia::Iam.config.region)
        "urn:#{partition}:#{SERVICE}:#{region}:#{account}:#{resource_type}/#{resource_id}"
      end

      # Splits into at most 6 `:`-fields; the final field carries
      # "resource_type/resource_id" and is split once on the first "/". Never
      # raises — a non-URN string yields an invalid Parsed.
      def parse(str)
        parts = str.to_s.split(":", 6)
        return blank unless parts.size == 6 && parts.first == "urn"

        _urn, partition, service, region, account, resource = parts
        resource_type, resource_id = resource.to_s.split("/", 2)
        Parsed.new(
          partition: partition,
          service: service,
          region: region,
          account: account,
          resource_type: resource_type,
          resource_id: resource_id
        )
      end

      def blank
        Parsed.new(partition: nil, service: nil, region: nil, account: nil, resource_type: nil, resource_id: nil)
      end
    end
  end
end
