module Iam
  # Gives a model a URN (ADR 0002 §4). Ports the ergonomics of the 2019
  # Ros::UrnConcern (to_urn / find_by_urn / overridable urn_id) — concept only,
  # rewritten clean.
  #
  #   class_attribute-style hooks:
  #     urn_resource_type "user"   # defaults to the demodulized, underscored class
  #     urn_id :access_key_id      # column used as resource_id (default :id)
  #
  # The account segment always comes from Iam.current_account_handle — the single
  # sanctioned routing source (ADR 0002/0003).
  module HasUrn
    extend ActiveSupport::Concern

    included do
      class_attribute :urn_id_attribute, instance_accessor: false, default: :id
      class_attribute :urn_resource_type_token, instance_accessor: false, default: nil
    end

    class_methods do
      # Override the resource_id column (default :id).
      def urn_id(attribute)
        self.urn_id_attribute = attribute
      end

      # Override the URN resource_type token (default: demodulized/underscored
      # class name, e.g. Iam::HumanPrincipal => "human_principal").
      def urn_resource_type(token)
        self.urn_resource_type_token = token.to_s
      end

      def default_urn_resource_type
        urn_resource_type_token || name.demodulize.underscore
      end

      # Find a record by its URN, scoped to this model's resource type. Returns
      # nil for a malformed URN or a resource_type mismatch.
      def find_by_urn(urn_string)
        parsed = Iam::Urn.parse(urn_string)
        return nil unless parsed.valid? && parsed.resource_type == default_urn_resource_type

        find_by(urn_id_attribute => parsed.resource_id)
      end
    end

    def to_urn
      Iam::Urn.build(
        account: Iam.current_account_handle,
        resource_type: self.class.default_urn_resource_type,
        resource_id: public_send(self.class.urn_id_attribute)
      )
    end

    def urn_resource_type
      self.class.default_urn_resource_type
    end
  end
end
