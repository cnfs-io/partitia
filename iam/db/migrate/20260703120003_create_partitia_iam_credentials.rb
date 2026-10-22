class CreateIamCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :iam_credentials do |t|
      t.string :access_key_id, null: false
      t.string :secret_digest, null: false   # HMAC-SHA256 digest; never plaintext
      t.references :owner, polymorphic: true, null: false

      t.timestamps
    end

    add_index :iam_credentials, :access_key_id, unique: true
  end
end
