# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:name) { |n| "User #{n}" }
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password" }

    trait :admin do
      admin { true }
    end
  end

  factory :budget do
    association :borrower, factory: :user
    amount_eur_cents { 100_000 }
    collateral_eur_cents { 200_000 }
    period_start { Date.current.beginning_of_month }
    period_end { Date.current.end_of_month }
    status { :pending }
  end
end
