class CreatePartitiaIamPrincipals < ActiveRecord::Migration[8.1]
  def change
    create_table :partitia_iam_principals do |t|
      t.string :type, null: false   # STI discriminator (human / machine)
      t.string :name, null: false
      # Human identity attributes (from the IdP assertion / provisioning);
      # nullable because machines have neither (ADR 0004).
      t.string :email
      # Distinguished-principal flag; meaningful only on humans (ADR 0004).
      t.boolean :root, null: false, default: false
      # Bootstrap / invite link token (Piece 3): HMAC digest only, never
      # plaintext, with an expiry. Both nullable — most principals never hold one.
      t.string :link_token_digest
      t.datetime :link_token_expires_at

      t.timestamps
    end

    add_index :partitia_iam_principals, :type
    # At most one root per database (ADR 0004), enforced at the DB layer via a
    # partial unique index. SQLite supports partial indexes.
    add_index :partitia_iam_principals, :root, unique: true, where: "root"
  end
end
