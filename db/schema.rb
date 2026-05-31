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

ActiveRecord::Schema[8.1].define(version: 2026_05_31_130000) do
  create_table "btc_accounts", force: :cascade do |t|
    t.bigint "balance_sats", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_btc_accounts_on_user_id", unique: true
  end

  create_table "budgets", force: :cascade do |t|
    t.integer "amount_eur_cents", null: false
    t.integer "borrower_id", null: false
    t.integer "collateral_eur_cents", null: false
    t.datetime "created_at", null: false
    t.integer "investor_id"
    t.decimal "peg_eur_per_btc", precision: 16, scale: 2
    t.date "period_end", null: false
    t.date "period_start", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["borrower_id"], name: "index_budgets_on_borrower_id"
    t.index ["investor_id"], name: "index_budgets_on_investor_id"
  end

  create_table "collateral_locks", force: :cascade do |t|
    t.bigint "amount_sats", null: false
    t.integer "budget_id", null: false
    t.datetime "created_at", null: false
    t.datetime "locked_at", null: false
    t.datetime "updated_at", null: false
    t.index ["budget_id"], name: "index_collateral_locks_on_budget_id", unique: true
  end

  create_table "settlements", force: :cascade do |t|
    t.bigint "btc_to_investor_sats", null: false
    t.integer "budget_id", null: false
    t.datetime "created_at", null: false
    t.decimal "end_btc_eur_rate", precision: 16, scale: 2, null: false
    t.datetime "executed_at", null: false
    t.bigint "total_btc_to_holders_sats", null: false
    t.datetime "updated_at", null: false
    t.index ["budget_id"], name: "index_settlements_on_budget_id", unique: true
  end

  create_table "token_accounts", force: :cascade do |t|
    t.integer "balance_cents", default: 0, null: false
    t.integer "budget_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["budget_id"], name: "index_token_accounts_on_budget_id"
    t.index ["user_id", "budget_id"], name: "index_token_accounts_on_user_id_and_budget_id", unique: true
    t.index ["user_id"], name: "index_token_accounts_on_user_id"
  end

  create_table "token_transfers", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.integer "budget_id", null: false
    t.datetime "created_at", null: false
    t.integer "from_user_id", null: false
    t.integer "to_user_id", null: false
    t.datetime "updated_at", null: false
    t.index ["budget_id"], name: "index_token_transfers_on_budget_id"
    t.index ["from_user_id"], name: "index_token_transfers_on_from_user_id"
    t.index ["to_user_id"], name: "index_token_transfers_on_to_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "btc_accounts", "users"
  add_foreign_key "budgets", "users", column: "borrower_id"
  add_foreign_key "budgets", "users", column: "investor_id"
  add_foreign_key "collateral_locks", "budgets"
  add_foreign_key "settlements", "budgets"
  add_foreign_key "token_accounts", "budgets"
  add_foreign_key "token_accounts", "users"
  add_foreign_key "token_transfers", "budgets"
  add_foreign_key "token_transfers", "users", column: "from_user_id"
  add_foreign_key "token_transfers", "users", column: "to_user_id"
end
