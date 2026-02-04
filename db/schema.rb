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

ActiveRecord::Schema[8.1].define(version: 2026_02_03_083628) do
  create_table "room_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "role", default: "member", null: false
    t.integer "room_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["room_id", "user_id"], name: "index_room_memberships_on_room_id_and_user_id", unique: true
    t.index ["room_id"], name: "index_room_memberships_on_room_id"
    t.index ["user_id"], name: "index_room_memberships_on_user_id"
  end

  create_table "room_messages", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.integer "room_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["room_id"], name: "index_room_messages_on_room_id"
    t.index ["user_id"], name: "index_room_messages_on_user_id"
  end

  create_table "room_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "exit_code"
    t.datetime "finished_at"
    t.integer "room_id", null: false
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.text "stderr"
    t.text "stdout"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["room_id"], name: "index_room_runs_on_room_id"
    t.index ["user_id"], name: "index_room_runs_on_user_id"
  end

  create_table "rooms", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "owner_id", null: false
    t.string "slug", null: false
    t.string "template_key", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id"], name: "index_rooms_on_owner_id"
    t.index ["slug"], name: "index_rooms_on_slug", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "room_memberships", "rooms"
  add_foreign_key "room_memberships", "users"
  add_foreign_key "room_messages", "rooms"
  add_foreign_key "room_messages", "users"
  add_foreign_key "room_runs", "rooms"
  add_foreign_key "room_runs", "users"
  add_foreign_key "rooms", "users", column: "owner_id"
end
