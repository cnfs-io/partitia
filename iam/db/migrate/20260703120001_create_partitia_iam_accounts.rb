class CreateIamAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :iam_accounts do |t|
      t.string :name, null: false

      t.timestamps

      # Singleton enforcement at the DB layer (ADR 0003): only id = 1 may exist.
      t.check_constraint "id = 1", name: "iam_accounts_singleton"
    end
  end
end
