require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]

  private

  # Controllers register asynchronously after Turbo has loaded the page (each one is a
  # separate module import), so on a slow machine a click can land before its action is
  # wired up. Wait until the controller is connected on the first matching element.
  def wait_for_stimulus(identifier, selector = "[data-controller~='#{identifier}']")
    page.document.synchronize(10) do
      connected = page.evaluate_script(<<~JS)
        (() => {
          const element = document.querySelector(#{selector.to_json})
          return Boolean(element && window.Stimulus?.getControllerForElementAndIdentifier(element, #{identifier.to_json}))
        })()
      JS
      raise Capybara::ExpectationNotMet, "Stimulus controller #{identifier} isn't connected on #{selector}" unless connected
    end
  end

  # Wait for Turbo to finish navigating/submitting before proceeding.
  # Uses aria-busy (set by Turbo) and custom data attributes (set in application.js).
  # See: https://island94.org/2026/03/a-bulletproof-wait_for_turbo-test-helper
  def wait_for_turbo
    return if Capybara.current_driver == :rack_test

    page.assert_no_selector(
      "html[aria-busy], form[aria-busy], turbo-frame[aria-busy], html[data-turbo-not-loaded], html[data-turbo-loading], html[data-turbo-preview]",
      visible: :all
    )
  end

  # Poll database until condition is met (replaces fragile sleep + assert)
  def assert_db_change(condition, timeout: 5)
    deadline = Time.now + timeout
    until condition.call
      raise "Database condition not met within #{timeout}s" if Time.now > deadline
      sleep 0.2
    end
  end
end
