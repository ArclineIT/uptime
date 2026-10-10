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

ActiveRecord::Schema[8.1].define(version: 2026_10_10_060001) do
  create_table "alert_channels", force: :cascade do |t|
    t.string "name", null: false
    t.string "kind", null: false
    t.string "url"
    t.string "token"
    t.integer "priority", default: 5, null: false
    t.text "recipients"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_alert_channels_on_name", unique: true
  end

  create_table "alert_routes", force: :cascade do |t|
    t.integer "monitor_id", null: false
    t.integer "alert_channel_id", null: false
    t.index ["alert_channel_id"], name: "index_alert_routes_on_alert_channel_id"
    t.index ["monitor_id", "alert_channel_id"], name: "index_alert_routes_on_monitor_id_and_alert_channel_id", unique: true
    t.index ["monitor_id"], name: "index_alert_routes_on_monitor_id"
  end

  create_table "checks", force: :cascade do |t|
    t.integer "monitor_id", null: false
    t.boolean "up", default: false, null: false
    t.integer "status_code", default: 0, null: false
    t.integer "response_ms", default: 0, null: false
    t.string "error", default: "", null: false
    t.datetime "checked_at", null: false
    t.index ["checked_at"], name: "index_checks_on_checked_at"
    t.index ["monitor_id", "checked_at"], name: "index_checks_on_monitor_id_and_checked_at"
  end

  create_table "incidents", force: :cascade do |t|
    t.integer "monitor_id", null: false
    t.datetime "started_at", null: false
    t.datetime "resolved_at"
    t.datetime "last_alerted_at"
    t.string "reason", default: "", null: false
    t.index ["monitor_id"], name: "index_incidents_on_monitor_id"
    t.index ["started_at"], name: "index_incidents_on_started_at"
  end

  create_table "maintenance_windows", force: :cascade do |t|
    t.integer "monitor_id", null: false
    t.string "days", default: "*", null: false
    t.string "starts_at", null: false
    t.string "ends_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["monitor_id"], name: "index_maintenance_windows_on_monitor_id"
  end

  create_table "monitors", force: :cascade do |t|
    t.string "name", null: false
    t.string "kind", null: false
    t.boolean "enabled", default: true, null: false
    t.string "url"
    t.string "http_method", default: "GET", null: false
    t.text "body"
    t.json "headers", default: {}, null: false
    t.integer "expected_status", default: 200, null: false
    t.string "contains"
    t.string "host"
    t.integer "port"
    t.integer "expiry_warning_days", default: 14, null: false
    t.string "expected_ip"
    t.integer "max_response_ms", default: 0, null: false
    t.integer "interval", default: 60, null: false
    t.integer "timeout", default: 10, null: false
    t.datetime "last_checked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_monitors_on_name", unique: true
  end

  add_foreign_key "alert_routes", "alert_channels", on_delete: :cascade
  add_foreign_key "alert_routes", "monitors", on_delete: :cascade
  add_foreign_key "checks", "monitors", on_delete: :cascade
  add_foreign_key "incidents", "monitors", on_delete: :cascade
  add_foreign_key "maintenance_windows", "monitors", on_delete: :cascade
end
