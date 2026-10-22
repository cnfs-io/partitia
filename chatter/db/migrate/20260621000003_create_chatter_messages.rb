class CreateChatterMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :chatter_messages do |t|
      t.references :conversation, null: false, foreign_key: { to_table: :chatter_conversations }
      t.references :sender, polymorphic: true, null: false
      t.text :content, null: false

      t.timestamps
    end

    add_index :chatter_messages, %i[conversation_id created_at]
  end
end
