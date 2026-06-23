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

ActiveRecord::Schema[8.1].define(version: 2026_06_23_140000) do
  create_table "ad_risk_expressions", force: :cascade do |t|
    t.string "citation"
    t.text "classification_trigger"
    t.string "country", null: false
    t.datetime "created_at", null: false
    t.string "fact_id"
    t.string "keyword_ko"
    t.string "keyword_native"
    t.string "risk_level"
    t.datetime "updated_at", null: false
    t.index ["country"], name: "index_ad_risk_expressions_on_country"
  end

  create_table "annotation_comments", force: :cascade do |t|
    t.integer "annotation_id", null: false
    t.string "attachment_name"
    t.integer "author_id", null: false
    t.text "body"
    t.datetime "created_at", null: false
    t.integer "parent_id"
    t.datetime "updated_at", null: false
    t.index ["annotation_id"], name: "index_annotation_comments_on_annotation_id"
    t.index ["author_id"], name: "index_annotation_comments_on_author_id"
    t.index ["parent_id"], name: "index_annotation_comments_on_parent_id"
  end

  create_table "annotations", force: :cascade do |t|
    t.string "after_text"
    t.string "before_text"
    t.float "box_h"
    t.float "box_w"
    t.float "box_x"
    t.float "box_y"
    t.string "category"
    t.integer "component_version_id", null: false
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.integer "position", default: 0
    t.datetime "resolved_at"
    t.integer "resolved_by_id"
    t.integer "resolved_in_version_id"
    t.integer "seq"
    t.string "status", default: "open"
    t.datetime "updated_at", null: false
    t.index ["component_version_id", "seq"], name: "index_annotations_on_component_version_id_and_seq"
    t.index ["component_version_id"], name: "index_annotations_on_component_version_id"
    t.index ["created_by_id"], name: "index_annotations_on_created_by_id"
    t.index ["resolved_by_id"], name: "index_annotations_on_resolved_by_id"
    t.index ["resolved_in_version_id"], name: "index_annotations_on_resolved_in_version_id"
  end

  create_table "component_versions", force: :cascade do |t|
    t.string "change_reason"
    t.integer "component_id", null: false
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.boolean "current", default: false
    t.string "image_name"
    t.string "label"
    t.datetime "updated_at", null: false
    t.integer "version_number", null: false
    t.index ["component_id", "version_number"], name: "index_component_versions_on_component_id_and_version_number"
    t.index ["component_id"], name: "index_component_versions_on_component_id"
    t.index ["created_by_id"], name: "index_component_versions_on_created_by_id"
  end

  create_table "components", force: :cascade do |t|
    t.string "component_type", null: false
    t.datetime "created_at", null: false
    t.integer "position", default: 0
    t.integer "product_id", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id", "position"], name: "index_components_on_product_id_and_position"
    t.index ["product_id"], name: "index_components_on_product_id"
  end

  create_table "ingredient_limits", force: :cascade do |t|
    t.string "cas"
    t.string "category"
    t.string "citation"
    t.string "country", null: false
    t.datetime "created_at", null: false
    t.string "fact_id"
    t.string "inci_canonical", null: false
    t.decimal "max_pct", precision: 8, scale: 4
    t.string "max_pct_unit"
    t.string "restriction_type"
    t.string "source_url"
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["country", "inci_canonical"], name: "index_ingredient_limits_on_country_and_inci_canonical"
  end

  create_table "ingredients", force: :cascade do |t|
    t.string "cas"
    t.integer "component_version_id", null: false
    t.datetime "created_at", null: false
    t.decimal "declared_pct", precision: 6, scale: 2
    t.string "inci_canonical"
    t.string "inci_name"
    t.integer "position", default: 0
    t.datetime "updated_at", null: false
    t.index ["component_version_id"], name: "index_ingredients_on_component_version_id"
  end

  create_table "label_requirements", force: :cascade do |t|
    t.string "citation"
    t.string "country", null: false
    t.datetime "created_at", null: false
    t.string "fact_id"
    t.string "item"
    t.string "location"
    t.string "match_keyword"
    t.string "parent_law"
    t.text "required_text"
    t.datetime "updated_at", null: false
    t.index ["country"], name: "index_label_requirements_on_country"
  end

  create_table "label_texts", force: :cascade do |t|
    t.integer "component_version_id", null: false
    t.text "content"
    t.string "country"
    t.datetime "created_at", null: false
    t.string "language"
    t.string "text_type", default: "label"
    t.datetime "updated_at", null: false
    t.index ["component_version_id"], name: "index_label_texts_on_component_version_id"
  end

  create_table "product_members", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "product_id", null: false
    t.string "role", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["product_id"], name: "index_product_members_on_product_id"
    t.index ["user_id"], name: "index_product_members_on_user_id"
  end

  create_table "products", force: :cascade do |t|
    t.string "channel"
    t.string "code"
    t.string "country"
    t.datetime "created_at", null: false
    t.date "deadline"
    t.string "name", null: false
    t.string "notion_url"
    t.integer "owner_id"
    t.integer "parent_id"
    t.integer "position", default: 0
    t.string "product_type", default: "기획"
    t.datetime "updated_at", null: false
    t.index ["owner_id"], name: "index_products_on_owner_id"
    t.index ["parent_id"], name: "index_products_on_parent_id"
  end

  create_table "screening_findings", force: :cascade do |t|
    t.float "box_h"
    t.float "box_w"
    t.float "box_x"
    t.float "box_y"
    t.string "citation"
    t.integer "confidence", default: 80
    t.datetime "created_at", null: false
    t.string "decision"
    t.string "element_type"
    t.boolean "human_review_required", default: false
    t.text "issue_description"
    t.integer "position", default: 0
    t.text "recommended_action"
    t.integer "screening_run_id", null: false
    t.string "severity"
    t.string "subject"
    t.datetime "updated_at", null: false
    t.index ["screening_run_id"], name: "index_screening_findings_on_screening_run_id"
  end

  create_table "screening_runs", force: :cascade do |t|
    t.datetime "approved_at"
    t.integer "approved_by_id"
    t.integer "component_version_id", null: false
    t.string "country", null: false
    t.datetime "created_at", null: false
    t.string "decision"
    t.integer "requested_by_id"
    t.string "status", default: "completed"
    t.text "summary"
    t.datetime "updated_at", null: false
    t.index ["approved_by_id"], name: "index_screening_runs_on_approved_by_id"
    t.index ["component_version_id"], name: "index_screening_runs_on_component_version_id"
    t.index ["requested_by_id"], name: "index_screening_runs_on_requested_by_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "avatar_color", default: "#8e0300"
    t.datetime "created_at", null: false
    t.string "email"
    t.string "name", null: false
    t.string "role", default: "pm", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "annotation_comments", "annotation_comments", column: "parent_id"
  add_foreign_key "annotation_comments", "annotations"
  add_foreign_key "annotation_comments", "users", column: "author_id"
  add_foreign_key "annotations", "component_versions"
  add_foreign_key "annotations", "component_versions", column: "resolved_in_version_id"
  add_foreign_key "annotations", "users", column: "created_by_id"
  add_foreign_key "annotations", "users", column: "resolved_by_id"
  add_foreign_key "component_versions", "components"
  add_foreign_key "component_versions", "users", column: "created_by_id"
  add_foreign_key "components", "products"
  add_foreign_key "ingredients", "component_versions"
  add_foreign_key "label_texts", "component_versions"
  add_foreign_key "product_members", "products"
  add_foreign_key "product_members", "users"
  add_foreign_key "products", "products", column: "parent_id"
  add_foreign_key "products", "users", column: "owner_id"
  add_foreign_key "screening_findings", "screening_runs"
  add_foreign_key "screening_runs", "component_versions"
  add_foreign_key "screening_runs", "users", column: "approved_by_id"
  add_foreign_key "screening_runs", "users", column: "requested_by_id"
end
