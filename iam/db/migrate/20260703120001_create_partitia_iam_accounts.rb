class CreatePartitiaIamAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :partitia_iam_accounts do |t|
      t.string :name, null: false

      t.timestamps

      # Singleton enforcement at the DB layer (ADR 0003): only id = 1 may exist.
      t.check_constraint "id = 1", name: "partitia_iam_accounts_singleton"
    end
  end
end
