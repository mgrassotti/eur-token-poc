# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Locale switching", type: :request do
  let(:user) { create(:user, name: "Alice") }

  it "renders the login page in English when requested" do
    get login_path(locale: :en)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Sign in")
    expect(response.body).to include("Eng")
    expect(response.body).to include("Ita")
    expect(response.body).to include("Database has no demo users.")
  end

  it "persists the selected locale across requests" do
    get login_path(locale: :en)
    get login_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Sign in")
    expect(response.body).not_to include("Database senza utenti demo.")
  end

  it "uses the selected locale after login redirects" do
    post session_path(locale: :en), params: { email: user.email, password: "password" }
    follow_redirect!

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Hello, Alice")
    expect(response.body).to include("Deposit to reserve account")
  end
end
