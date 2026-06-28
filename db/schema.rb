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

ActiveRecord::Schema[8.1].define(version: 2026_06_28_130000) do
  create_table "btc_accounts", force: :cascade do |t|
    t.bigint "balance_sats", default: 0, null: false
    t.string "bitcoind_wallet_name"
    t.datetime "created_at", null: false
    t.string "escrow_identity_pubkey"
    t.string "escrow_identity_wif"
    t.string "node_pubkey"
    t.string "rgb_mnemonic"
    t.string "rgb_wallet_id"
    t.string "rln_node_url"
    t.string "rln_token"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["bitcoind_wallet_name"], name: "index_btc_accounts_on_bitcoind_wallet_name", unique: true, where: "bitcoind_wallet_name IS NOT NULL"
    t.index ["user_id"], name: "index_btc_accounts_on_user_id", unique: true
  end

  create_table "budgets", force: :cascade do |t|
    t.integer "amount_eur_cents", null: false
    t.integer "borrower_id", null: false
    t.bigint "borrower_locked_sats", default: 0, null: false
    t.string "bot_pubkey"
    t.integer "collateral_eur_cents", null: false
    t.datetime "created_at", null: false
    t.string "escrow_txid"
    t.integer "escrow_vout"
    t.bigint "genesis_block_height"
    t.integer "investor_id"
    t.bigint "investor_locked_sats", default: 0, null: false
    t.string "investor_pubkey"
    t.bigint "maturity_block_height"
    t.decimal "peg_eur_per_btc", precision: 16, scale: 2
    t.string "peg_party_pubkey"
    t.date "period_end", null: false
    t.date "period_start", null: false
    t.integer "rate_bps_monthly", default: 100, null: false
    t.json "recovery_package"
    t.integer "refund_delay_blocks", default: 1008, null: false
    t.string "rgb_asset_id"
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

  create_table "dlc_contracts", force: :cascade do |t|
    t.integer "budget_id", null: false
    t.datetime "created_at", null: false
    t.string "ddk_contract_id"
    t.string "funding_txid"
    t.integer "funding_vout"
    t.bigint "investor_collateral_sats"
    t.bigint "maturity_epoch"
    t.integer "num_digits"
    t.text "oracle_announcement"
    t.string "oracle_event_id", null: false
    t.bigint "peg_collateral_sats"
    t.integer "status", default: 0, null: false
    t.string "unit"
    t.datetime "updated_at", null: false
    t.index ["budget_id"], name: "index_dlc_contracts_on_budget_id", unique: true
  end

  create_table "dlc_settlements", force: :cascade do |t|
    t.text "attestation"
    t.integer "budget_id", null: false
    t.string "cet_txid"
    t.datetime "created_at", null: false
    t.integer "dlc_contract_id", null: false
    t.datetime "executed_at"
    t.bigint "investor_sats"
    t.bigint "outcome"
    t.bigint "peg_pot_sats"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["budget_id"], name: "index_dlc_settlements_on_budget_id", unique: true
    t.index ["dlc_contract_id"], name: "index_dlc_settlements_on_dlc_contract_id"
  end

  create_table "investor_yield_payouts", force: :cascade do |t|
    t.decimal "btc_eur_per_btc", precision: 16, scale: 2, null: false
    t.bigint "btc_sats", null: false
    t.integer "budget_id", null: false
    t.datetime "created_at", null: false
    t.datetime "paid_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["budget_id"], name: "index_investor_yield_payouts_on_budget_id"
    t.index ["user_id"], name: "index_investor_yield_payouts_on_user_id"
  end

  create_table "market_rates", force: :cascade do |t|
    t.bigint "bitcoin_block_height", default: 0, null: false
    t.decimal "btc_eur_per_btc", precision: 16, scale: 2
    t.datetime "created_at", null: false
    t.integer "set_by_id"
    t.datetime "updated_at", null: false
    t.index ["set_by_id"], name: "index_market_rates_on_set_by_id"
  end

  create_table "rgb_assignments", force: :cascade do |t|
    t.string "assignment_id", null: false
    t.integer "budget_id", null: false
    t.datetime "created_at", null: false
    t.string "holder_pubkey", null: false
    t.integer "notional_share_cents", default: 0, null: false
    t.string "parent_assignment_id"
    t.string "rgb_asset_id"
    t.string "rgb_recipient_id"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["assignment_id"], name: "index_rgb_assignments_on_assignment_id", unique: true
    t.index ["budget_id", "user_id"], name: "index_rgb_assignments_on_budget_id_and_user_id", unique: true
    t.index ["budget_id"], name: "index_rgb_assignments_on_budget_id"
    t.index ["user_id"], name: "index_rgb_assignments_on_user_id"
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
    t.json "rgb_consignment"
    t.string "rgb_transfer_txid"
    t.integer "to_user_id", null: false
    t.datetime "updated_at", null: false
    t.index ["budget_id"], name: "index_token_transfers_on_budget_id"
    t.index ["from_user_id"], name: "index_token_transfers_on_from_user_id"
    t.index ["to_user_id"], name: "index_token_transfers_on_to_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
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
  add_foreign_key "dlc_contracts", "budgets"
  add_foreign_key "dlc_settlements", "budgets"
  add_foreign_key "dlc_settlements", "dlc_contracts"
  add_foreign_key "investor_yield_payouts", "budgets"
  add_foreign_key "investor_yield_payouts", "users"
  add_foreign_key "market_rates", "users", column: "set_by_id"
  add_foreign_key "rgb_assignments", "budgets"
  add_foreign_key "rgb_assignments", "users"
  add_foreign_key "settlements", "budgets"
  add_foreign_key "token_accounts", "budgets"
  add_foreign_key "token_accounts", "users"
  add_foreign_key "token_transfers", "budgets"
  add_foreign_key "token_transfers", "users", column: "from_user_id"
  add_foreign_key "token_transfers", "users", column: "to_user_id"
end
