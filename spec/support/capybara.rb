# frozen_string_literal: true

require "fileutils"
require "capybara/rspec"

Capybara.default_max_wait_time = 30

RSpec.configure do |config|
  config.before(:each, type: :system) do
    self.use_transactional_tests = false
    driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]
  end

  config.after(:each, type: :system) do |example|
    next unless example.exception

    screenshot_dir = Rails.root.join("tmp/capybara")
    FileUtils.mkdir_p(screenshot_dir)
    path = screenshot_dir.join("system-failure-#{Time.now.to_i}.png")
    save_screenshot(path)
    warn "Screenshot salvato: #{path}"
  end
end
