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

ActiveRecord::Schema[8.1].define(version: 2026_10_28_193417) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "api_usages", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.string "provider", null: false
    t.string "operation", null: false
    t.integer "units", default: 0, null: false
    t.decimal "cost_usd", precision: 10, scale: 6, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "provider"], name: "index_api_usages_on_project_id_and_provider"
    t.index ["project_id"], name: "index_api_usages_on_project_id"
  end

  create_table "audio_tracks", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.string "kind", null: false
    t.string "voice_name"
    t.decimal "speed", precision: 3, scale: 2, default: "1.0", null: false
    t.integer "duration_ms"
    t.string "status", default: "pending", null: false
    t.text "error"
    t.string "script_digest"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "confirmed_at"
    t.integer "volume", default: 18, null: false
    t.string "title"
    t.string "credit"
    t.string "license"
    t.string "source_url"
    t.string "page_url"
    t.jsonb "timings", default: [], null: false
    t.index ["project_id", "kind"], name: "index_audio_tracks_on_project_id_and_kind", unique: true
    t.index ["project_id"], name: "index_audio_tracks_on_project_id"
  end

  create_table "credit_transactions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "project_id"
    t.integer "amount", null: false
    t.integer "balance_after", null: false
    t.string "reason", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_credit_transactions_on_project_id"
    t.index ["user_id", "created_at"], name: "index_credit_transactions_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_credit_transactions_on_user_id"
  end

  create_table "projects", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "title", null: false
    t.text "prompt"
    t.string "tone"
    t.integer "target_length_minutes"
    t.string "status", default: "draft", null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "render_error"
    t.string "yt_title"
    t.text "yt_description"
    t.string "yt_tags", default: [], null: false, array: true
    t.string "yt_category"
    t.index ["user_id", "created_at"], name: "index_projects_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_projects_on_user_id"
  end

  create_table "scene_images", force: :cascade do |t|
    t.bigint "scene_id", null: false
    t.string "provider", null: false
    t.string "image_url"
    t.string "page_url"
    t.string "credit"
    t.string "license"
    t.boolean "selected", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "prompt"
    t.string "media_type", default: "image", null: false
    t.string "poster_url"
    t.integer "duration_ms"
    t.integer "clip_start_ms"
    t.text "description"
    t.string "taken_on"
    t.text "categories"
    t.index ["scene_id"], name: "index_scene_images_on_scene_id"
  end

  create_table "scenes", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.integer "position", null: false
    t.text "text", null: false
    t.integer "start_ms", null: false
    t.integer "duration_ms", null: false
    t.string "search_query"
    t.text "search_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "plan", default: {}, null: false
    t.string "ai_status"
    t.text "ai_error"
    t.string "media_check"
    t.text "media_note"
    t.index ["project_id", "position"], name: "index_scenes_on_project_id_and_position", unique: true
    t.index ["project_id"], name: "index_scenes_on_project_id"
  end

  create_table "scripts", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.text "body", default: "", null: false
    t.integer "version", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "version"], name: "index_scripts_on_project_id_and_version", unique: true
    t.index ["project_id"], name: "index_scripts_on_project_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "encrypted_password", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "credits_balance", default: 0, null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "voice_samples", force: :cascade do |t|
    t.string "voice_name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["voice_name"], name: "index_voice_samples_on_voice_name", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "api_usages", "projects"
  add_foreign_key "audio_tracks", "projects"
  add_foreign_key "credit_transactions", "projects", on_delete: :nullify
  add_foreign_key "credit_transactions", "users"
  add_foreign_key "projects", "users"
  add_foreign_key "scene_images", "scenes"
  add_foreign_key "scenes", "projects"
  add_foreign_key "scripts", "projects"
end
