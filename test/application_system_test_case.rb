require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # A browser test waits for what it asks about. Two seconds is enough on an idle
  # machine and not on a busy one, where the whole suite (and everything else) runs.
  Capybara.default_max_wait_time = 5

  # Chrome warns that the fixtures' password, "password", was found in a data breach. After the
  # first sign-in in a new browser, that warning takes the keyboard and keys never reach the page.
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |options|
    options.add_preference("profile.password_manager_leak_detection", false)
  end

  # When the service worker installed on the first page takes control of it, Chrome drops
  # the next click now and then. The tests don't need it.
  setup do
    page.driver.browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument",
      source: "navigator.serviceWorker.register = () => Promise.resolve()")
  end

  # The app server runs in this process, so the sockets of the last test outlive
  # it: the browser is torn down by loading a blank page, which leaves them to
  # time out rather than unsubscribe. One closing halfway through the next test
  # says its person left while they are on the page. So they are closed first,
  # and the per-process tab counts start from zero.
  setup do
    ActionCable.server.connections.dup.each(&:close)
    deadline = Time.current + 2.seconds
    sleep 0.05 until ActionCable.server.connections.empty? || Time.current > deadline

    ChatPresence.reset!
    ToolPresence.reset!
    DocumentPresence.reset!
  end

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

  # The first sign-in of a run can take a while on a busy machine
  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "password"
    click_on "Sign In"
    assert_selector ".sidebar", wait: 15
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
