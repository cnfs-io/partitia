# frozen_string_literal: true

# Global database: the tenant registry. Read in place from this engine's
# db/global_migrate path (the host wires `global` -> db/global_migrate in
# database.yml via the install generator).
class CreateTenants < ActiveRecord::Migration[8.1]
  def change
    create_table :tenants do |t|
      t.string :name, null: false
      t.string :subdomain, null: false

      t.timestamps
    end

    add_index :tenants, :subdomain, unique: true
  end
end
