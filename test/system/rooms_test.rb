# frozen_string_literal: true

require "application_system_test_case"

class RoomsTest < ApplicationSystemTestCase
  LIVEKIT_ENV_KEYS = %w[LIVEKIT_URL LIVEKIT_API_KEY LIVEKIT_API_SECRET].freeze

  setup do
    @tool = tools(:my_room)
    sign_in_as users(:one)

    # Deterministic regardless of the developer's shell — these system tests
    # never talk to a real LiveKit server, so make sure it looks unconfigured.
    @previous_livekit_env = LIVEKIT_ENV_KEYS.index_with { |key| ENV[key] }
    LIVEKIT_ENV_KEYS.each { |key| ENV.delete(key) }
  end

  teardown do
    @previous_livekit_env.each { |key, value| ENV[key] = value }
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

  # Whether headless Chrome offers a camera has changed between builds; pin one with
  # CHROME_FOR_TESTING=<version> for bin/system-test if this stops failing without a camera.
  test "pre-join screen explains blocked camera/microphone access and offers a retry" do
    # Headless Chrome for Testing has no camera/mic and no fake-ui flag, so
    # getUserMedia rejects immediately — exercising the same failure path a
    # real user hits when they deny the permission prompt.
    visit tool_path(@tool)
    wait_for_turbo
    wait_for_stimulus "room"

    assert_selector "[data-room-target='preJoinError']:not(.hidden)", wait: 5
    assert_selector "[data-room-target='preJoinError']", text: /camera|microphone/i
    assert_selector "[data-room-target='preJoinError'] button", text: "Try again"
  end

  test "shows a clear error when LiveKit isn't configured" do
    visit tool_path(@tool)
    wait_for_turbo
    wait_for_stimulus "room"
    # Wait for the camera check (no camera in headless Chrome), so its error can't replace the one from joining
    assert_selector "[data-room-target='preJoinError']", text: /camera|microphone/i, wait: 5

    click_on "Join Room"

    assert_selector "[data-room-target='preJoinError']:not(.hidden)", wait: 5
    assert_selector "[data-room-target='preJoinError']", text: /aren't set up|couldn't reach|couldn't start/i
    # Never left the pre-join screen
    assert_selector "[data-room-target='preJoin']:not(.hidden)"
    assert_selector "[data-room-target='inCall'].hidden", visible: :all
  end

  test "a second click on Join while joining doesn't start a second join" do
    visit tool_path(@tool)
    wait_for_turbo
    wait_for_stimulus "room"
    assert_selector "[data-room-target='preJoinError']", text: /camera|microphone/i, wait: 5

    # Slow token requests down, and count them
    page.execute_script(<<~JS)
      window.__tokenRequests = 0
      const original = window.fetch
      window.fetch = (url, options) => {
        if (String(url).includes("/tokens")) {
          window.__tokenRequests++
          return new Promise(resolve => setTimeout(resolve, 1000)).then(() => original(url, options))
        }
        return original(url, options)
      }
    JS

    join = find("[data-room-target='joinButton']")
    join.click
    assert_selector "[data-room-target='joinButton'][disabled]"
    page.execute_script("arguments[0].click()", join)

    assert_selector "[data-room-target='preJoinError']", text: /aren't set up/i, wait: 5
    assert_no_selector "[data-room-target='joinButton'][disabled]"
    assert_equal 1, page.evaluate_script("window.__tokenRequests")
  end

  test "people in a call get 16:9 tiles as large as the room allows, never cropped to fit" do
    visit tool_path(@tool)
    wait_for_turbo
    wait_for_stimulus "room"

    # No video server here: show the call and seat people the way a joining room would
    page.execute_script(<<~JS)
      const element = document.querySelector("[data-controller~='room']")
      const room = window.Stimulus.getControllerForElementAndIdentifier(element, "room")
      room.preJoinTarget.classList.add("hidden")
      room.inCallTarget.classList.remove("hidden")
      room.renderParticipant({ identity: "anna", name: "Anna" })
    JS

    tile = <<~JS
      (() => {
        const grid = document.querySelector("[data-room-target='videoGrid']").getBoundingClientRect()
        const tiles = [...document.querySelectorAll("[data-participant-id]")].map(tile => tile.getBoundingClientRect())
        return {
          ratios: tiles.map(box => Math.round(box.width / box.height * 100)),
          inside: tiles.every(box => box.left >= grid.left && box.right <= grid.right + 1 && box.top >= grid.top && box.bottom <= grid.bottom + 1),
          touches: Math.round(grid.width - tiles[0].width) <= 34 || Math.round(grid.height - tiles[0].height) <= 34
        }
      })()
    JS

    assert_equal({ "ratios" => [ 178 ], "inside" => true, "touches" => true }, evaluate_script(tile))

    page.execute_script(<<~JS)
      const room = window.Stimulus.getControllerForElementAndIdentifier(document.querySelector("[data-controller~='room']"), "room")
      ;["bo", "cas", "dee", "eli"].forEach(identity => room.renderParticipant({ identity, name: identity }))
    JS

    layout = evaluate_script(tile)
    assert_equal [ 178 ] * 5, layout["ratios"]
    assert layout["inside"], "every tile fits inside the call"
  end
end
