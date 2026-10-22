# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_21_000011) do
  create_table "agents", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "chatter_conversations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "kind", default: 0, null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "chatter_memberships", force: :cascade do |t|
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "last_read_at"
    t.integer "participant_id", null: false
    t.string "participant_type", null: false
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "participant_type", "participant_id"], name: "index_chatter_memberships_on_conversation_and_participant", unique: true
    t.index ["conversation_id"], name: "index_chatter_memberships_on_conversation_id"
    t.index ["participant_type", "participant_id"], name: "index_chatter_memberships_on_participant"
  end

  create_table "chatter_messages", force: :cascade do |t|
    t.text "content", null: false
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.integer "sender_id", null: false
    t.string "sender_type", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "created_at"], name: "index_chatter_messages_on_conversation_id_and_created_at"
    t.index ["conversation_id"], name: "index_chatter_messages_on_conversation_id"
    t.index ["sender_type", "sender_id"], name: "index_chatter_messages_on_sender"
  end

  create_table "people", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "chatter_memberships", "chatter_conversations", column: "conversation_id"
  add_foreign_key "chatter_messages", "chatter_conversations", column: "conversation_id"
end
