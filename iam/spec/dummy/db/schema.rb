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

ActiveRecord::Schema[8.1].define(version: 2026_07_03_120004) do
  create_table "iam_accounts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.check_constraint "id = 1", name: "iam_accounts_singleton"
  end

  create_table "iam_credentials", force: :cascade do |t|
    t.string "access_key_id", null: false
    t.datetime "created_at", null: false
    t.integer "owner_id", null: false
    t.string "owner_type", null: false
    t.string "secret_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["access_key_id"], name: "index_iam_credentials_on_access_key_id", unique: true
    t.index ["owner_type", "owner_id"], name: "index_iam_credentials_on_owner"
  end

  create_table "iam_identity_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "issuer", null: false
    t.integer "principal_id", null: false
    t.string "subject", null: false
    t.datetime "updated_at", null: false
    t.index ["issuer", "subject"], name: "index_iam_identity_links_on_issuer_and_subject", unique: true
    t.index ["principal_id"], name: "index_iam_identity_links_on_principal_id"
  end

  create_table "iam_principals", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "link_token_digest"
    t.datetime "link_token_expires_at"
    t.string "name", null: false
    t.boolean "root", default: false, null: false
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.index ["root"], name: "index_iam_principals_on_root", unique: true, where: "root"
    t.index ["type"], name: "index_iam_principals_on_type"
  end

  add_foreign_key "iam_identity_links", "iam_principals", column: "principal_id"
end
