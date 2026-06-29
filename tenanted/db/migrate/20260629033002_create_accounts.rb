# frozen_string_literal: true

# Tenant database: the per-tenant settings singleton. Read in place from this
# engine's db/migrate path, which the install generator wires into the tenanted
# `primary` config's migrations_paths (via the CnfsSupport::TenantMigrations
# registry). Runs against every tenant database as it is provisioned.
#
# The CHECK (id = 1) constraint enforces the singleton at the database level:
# at most one row can ever exist, no matter how insertion is attempted.
class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts do |t|
      t.string :name, null: false

      t.timestamps

      t.check_constraint "id = 1", name: "accounts_singleton"
    end
  end
end
