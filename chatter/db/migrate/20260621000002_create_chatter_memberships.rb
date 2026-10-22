class CreateChatterMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :chatter_memberships do |t|
      t.references :conversation, null: false, foreign_key: { to_table: :chatter_conversations }
      t.references :participant, polymorphic: true, null: false
      t.integer :role, null: false, default: 0
      t.datetime :last_read_at

      t.timestamps
    end

    add_index :chatter_memberships,
      %i[conversation_id participant_type participant_id],
      unique: true,
      name: "index_chatter_memberships_on_conversation_and_participant"
  end
end
