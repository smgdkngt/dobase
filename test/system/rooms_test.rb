# frozen_string_literal: true

require "application_system_test_case"

class RoomsTest < ApplicationSystemTestCase
  setup do
    @tool = tools(:my_room)
    sign_in_as users(:one)
  end

  test "the video call library loads under the app's content security policy" do
    visit tool_path(@tool)
    wait_for_turbo
    wait_for_stimulus "room"

    loaded = page.evaluate_async_script(<<~JS)
      const done = arguments[0]
      import("livekit-client").then(module => done(typeof module.Room)).catch(error => done(String(error)))
    JS

    assert_equal "function", loaded
  end

  private

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "password"
    click_on "Sign In"
    assert_selector ".sidebar", wait: 5
  end
end
