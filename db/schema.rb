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

ActiveRecord::Schema[8.1].define(version: 2026_09_15_114525) do
  create_table "audience_queries", force: :cascade do |t|
    t.integer "audience_id", null: false
    t.datetime "created_at", null: false
    t.string "generated_by", null: false
    t.boolean "is_active", default: true, null: false
    t.string "query", null: false
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.index ["audience_id", "source", "query"], name: "index_audience_queries_on_audience_id_and_source_and_query", unique: true
    t.index ["audience_id"], name: "index_audience_queries_on_audience_id"
  end

  create_table "audiences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_audiences_on_slug", unique: true
  end

  create_table "classifications", force: :cascade do |t|
    t.datetime "classified_at", null: false
    t.float "confidence"
    t.datetime "created_at", null: false
    t.string "intent", null: false
    t.string "lens", null: false
    t.string "model", null: false
    t.integer "post_id", null: false
    t.string "side", null: false
    t.datetime "updated_at", null: false
    t.index ["lens", "side"], name: "index_classifications_on_lens_and_side"
    t.index ["post_id"], name: "index_classifications_on_post_id", unique: true
  end

  create_table "cluster_posts", force: :cascade do |t|
    t.integer "cluster_id", null: false
    t.datetime "created_at", null: false
    t.integer "post_id", null: false
    t.datetime "updated_at", null: false
    t.index ["cluster_id", "post_id"], name: "index_cluster_posts_on_cluster_id_and_post_id", unique: true
    t.index ["cluster_id"], name: "index_cluster_posts_on_cluster_id"
    t.index ["post_id"], name: "index_cluster_posts_on_post_id"
  end

  create_table "clusters", force: :cascade do |t|
    t.integer "audience_id", null: false
    t.datetime "created_at", null: false
    t.string "lens", null: false
    t.string "name", null: false
    t.text "representative_text"
    t.datetime "updated_at", null: false
    t.date "week_start", null: false
    t.index ["audience_id", "week_start", "lens"], name: "index_clusters_on_audience_id_and_week_start_and_lens"
    t.index ["audience_id"], name: "index_clusters_on_audience_id"
  end

  create_table "posts", force: :cascade do |t|
    t.integer "audience_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "external_id", null: false
    t.datetime "fetched_at", null: false
    t.json "metrics", null: false
    t.datetime "posted_at", null: false
    t.string "source", null: false
    t.text "text", null: false
    t.datetime "updated_at", null: false
    t.string "video_id"
    t.index ["audience_id", "posted_at"], name: "index_posts_on_audience_id_and_posted_at"
    t.index ["audience_id"], name: "index_posts_on_audience_id"
    t.index ["expires_at"], name: "index_posts_on_expires_at"
    t.index ["source", "external_id"], name: "index_posts_on_source_and_external_id", unique: true
  end

  create_table "subscribers", force: :cascade do |t|
    t.integer "audience_id", null: false
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "unsubscribed_at"
    t.datetime "updated_at", null: false
    t.json "utm", null: false
    t.index ["audience_id", "email"], name: "index_subscribers_on_audience_id_and_email", unique: true
    t.index ["audience_id"], name: "index_subscribers_on_audience_id"
  end

  create_table "weekly_snapshots", force: :cascade do |t|
    t.integer "audience_id", null: false
    t.integer "author_count", default: 0, null: false
    t.integer "cluster_id", null: false
    t.datetime "created_at", null: false
    t.string "lens", null: false
    t.float "opportunity_score"
    t.integer "post_count", default: 0, null: false
    t.integer "supply_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.date "week_start", null: false
    t.float "wow_change"
    t.index ["audience_id", "week_start", "lens", "cluster_id"], name: "index_weekly_snapshots_on_audience_week_lens_cluster", unique: true
    t.index ["audience_id"], name: "index_weekly_snapshots_on_audience_id"
    t.index ["cluster_id"], name: "index_weekly_snapshots_on_cluster_id"
  end

  add_foreign_key "audience_queries", "audiences"
  add_foreign_key "classifications", "posts"
  add_foreign_key "cluster_posts", "clusters"
  add_foreign_key "cluster_posts", "posts"
  add_foreign_key "clusters", "audiences"
  add_foreign_key "posts", "audiences"
  add_foreign_key "subscribers", "audiences"
  add_foreign_key "weekly_snapshots", "audiences"
  add_foreign_key "weekly_snapshots", "clusters"
end
