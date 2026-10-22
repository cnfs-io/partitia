class CreateChatterConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :chatter_conversations do |t|
      t.integer :kind, null: false, default: 0
      t.string :name

      t.timestamps
    end
  end
end
