module Partitia
  module Iam
    # The per-tenant settings singleton (ADR 0003 Decision 2, tenant plane).
    # Exactly one row exists in each tenant's own database (id pinned to 1). This
    # is the tenant's self-service config surface — NOT a routing anchor. The
    # routing handle lives on the gem's Tenant (ADR 0003); Account is config only,
    # so it deliberately carries no handle column.
    #
    # SINGLETON ENFORCEMENT (defense in depth):
    #   1. Database: a CHECK (id = 1) constraint on the table (see the migration)
    #      makes a second row physically impossible.
    #   2. Model: SINGLETON_ID + .instance provide the only sanctioned accessor,
    #      a find-or-create that always targets id 1.
    class Account < ApplicationRecord
      SINGLETON_ID = 1

      validates :name, presence: true
      # Guard against ever pointing at a non-singleton id at the model layer too.
      validates :id, inclusion: { in: [ SINGLETON_ID ] }

      class << self
        # The one and only Account row, created on first access. Attributes (e.g.
        # name:) are applied only when first creating it.
        def instance(**attributes)
          find_or_create_by!(id: SINGLETON_ID) do |account|
            account.assign_attributes(attributes)
            account.name ||= default_name
          end
        end

        private

        def default_name
          I18n.t("partitia_iam.account.default_name")
        end
      end

      # Singletons are never destroyed through normal flows; make that explicit.
      def destroy
        raise ActiveRecord::ReadOnlyRecord, I18n.t("partitia_iam.account.errors.undestroyable")
      end
    end
  end
end
