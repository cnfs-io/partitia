# frozen_string_literal: true

# Global database: the tenant registry. Read in place from this engine's
# db/global_migrate path (the host wires `global` -> db/global_migrate in
# database.yml via the install generator).
class CreatePartitiaTenantedTenants < ActiveRecord::Migration[8.1]
  def change
    create_table :partitia_tenanted_tenants do |t|
      # Immutable routing key (ADR 0002 §1): opaque, system-generated. Keys the
      # tenant database; access key ids and URNs embed it.
      t.string :handle, null: false
      # Mutable, human-facing lookup resolved *to* a handle.
      t.string :subdomain, null: false
      t.string :name, null: false
      # The tenant owner's email — consumed by provisioning hooks to seed the
      # root principal (ADR 0004). A fact about the tenant, so it lives here in
      # the global DB (ADR 0003 §4), not in the tenant's own Account.
      t.string :owner_email, null: false

      t.timestamps
    end

    add_index :partitia_tenanted_tenants, :handle, unique: true
    add_index :partitia_tenanted_tenants, :subdomain, unique: true
  end
end
