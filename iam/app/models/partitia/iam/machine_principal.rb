module Partitia
  module Iam
    # A machine (non-human) principal — services, workloads, agents. URN
    # resource_type "machine". Machines authenticate via credentials only (never
    # IdP assertions) and are never root (ADR 0004).
    class MachinePrincipal < Principal
      urn_resource_type "machine"

      validate :machines_are_never_root

      private

      def machines_are_never_root
        errors.add(:root, I18n.t("partitia_iam.principal.errors.machine_cannot_be_root")) if root?
      end
    end
  end
end
