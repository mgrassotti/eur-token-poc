# frozen_string_literal: true

module SystemTestHelpers
  DEMO_PASSWORD = "password"

  module_function

  def btc_amount_for(sats)
    format("%.8f", sats / 100_000_000.0)
  end

  def login_as(role)
    user = demo_user(role)
    visit login_path
    fill_in "Email", with: user.email
    fill_in "Password", with: DEMO_PASSWORD
    click_button "Log in"
    expect(page).to have_current_path(root_path, ignore_query: true)
    expect_logged_in_as!(user)
    user
  end

  def switch_to(role)
    user = demo_user(role)
    find("select#user_id").select(user.name)
    expect(page).to have_current_path(root_path, ignore_query: true)
    expect_logged_in_as!(user)
    user
  end

  def expect_logged_in_as!(user)
    if user.admin?
      expect(page).to have_css(".badge", text: "Admin")
    else
      expect(page).to have_content("Ciao, #{user.name}")
    end
  end

  def expect_no_error_flash!
    expect(page).not_to have_css(".alert-danger", text: /Nodo RGB|Internal Server Error|Escrow L1 non provisionato/i)
  end

  def deposit_reserve!(sats:)
    visit new_reserve_deposit_path
    fill_in "Importo (BTC)", with: btc_amount_for(sats)
    click_button "Conferma deposito"
    expect_no_error_flash!
    expect(page).to have_current_path(root_path, ignore_query: true)
  end

  def set_market_rate!(eur_per_btc)
    fill_in "€/BTC", with: eur_per_btc.to_s
    click_button "Aggiorna cambio"
    expect_no_error_flash!
    expect(page).to have_current_path(root_path, ignore_query: true)
  end

  def fill_date_field!(field_id, date)
    iso = date.strftime("%Y-%m-%d")
    field = find("##{field_id}")
    page.execute_script("arguments[0].value = arguments[1]; arguments[0].dispatchEvent(new Event('input', { bubbles: true }))", field.native, iso)
  end

  def create_spending_budget!(amount_eur:, period_start:, period_end:)
    visit new_budget_path
    fill_in "budget_amount_eur", with: amount_eur.to_s
    fill_date_field!("budget_period_start", period_start)
    fill_date_field!("budget_period_end", period_end)
    click_button "Crea ricarica"
    expect_no_error_flash!
    expect(page).to have_current_path(%r{/budgets/\d+}, ignore_query: true)
    budget = Budget.find(page.current_path[%r{/budgets/(\d+)}, 1])
    budget
  end

  def activate_budget!(budget)
    visit budget_path(budget)
    click_button "Accetta rischio e attiva la richiesta"
    expect(page).to have_content("Budget attivato", wait: 90)
    expect_no_error_flash!
    budget.reload
    expect(budget).to be_active
    expect(budget.l1_multisig_provisioned?).to be(true)
    expect(budget.rgb_asset_id).to be_present
  end

  def send_tokens!(to_user:, amount_eur:)
    visit new_token_transfer_path
    select to_user.name, from: "Destinatario"
    fill_in "Importo (€)", with: amount_eur.to_s
    click_button "Invia Denaro"
    expect_no_error_flash!
    expect(page).to have_current_path(root_path, ignore_query: true)
  end

  def advance_chain_to_maturity!(budget)
    fill_in "Altezza blocco", with: budget.maturity_block_height.to_s
    click_button "Aggiorna blocco"
    expect_no_error_flash!
    expect(page).to have_current_path(root_path, ignore_query: true)
    budget.reload
    expect(budget).to be_settled
  end

  def expect_rgb_card_visible!
    visit root_path unless page.has_css?(".card-header", text: "RGB (RLN)", wait: 0)
    expect(page).to have_css(".card", text: "RGB (RLN)")
    expect(page).not_to have_css(".border-danger", text: "Nodo RGB Lightning non raggiungibile")
  end
end

RSpec.configure do |config|
  config.include SystemTestHelpers, type: :system
  config.include DemoFlowHelpers, type: :system
end
