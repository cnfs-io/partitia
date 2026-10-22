class CreateIamIdentityLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :iam_identity_links do |t|
      # The IdP issuer URL and its `sub` claim. This is the ONLY place the IdP
      # subject is stored (ADR 0004) — nothing else references it.
      t.string :issuer, null: false
      t.string :subject, null: false
      t.references :principal, null: false, foreign_key: { to_table: :iam_principals }

      t.timestamps
    end

    # (issuer, subject) is unique per database — one IdP identity binds to at
    # most one principal (ADR 0004).
    add_index :iam_identity_links, [ :issuer, :subject ], unique: true
  end
end
