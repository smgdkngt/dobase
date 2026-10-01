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

  test "a camera that answers after the reader left the room is switched off again" do
    visit tool_files_path(tools(:my_files))
    wait_for_turbo
    # A camera that answers when the test says so
    page.execute_script(<<~JS)
      const canvas = document.createElement("canvas")
      canvas.getContext("2d")
      window.__camera = canvas.captureStream()
      navigator.mediaDevices.getUserMedia = () => new Promise(resolve => { window.__answer = () => resolve(window.__camera) })
    JS

    find(".sidebar a", text: @tool.name).click
    wait_for_stimulus "room"
    find(".sidebar a", text: "My Files").click
    assert_selector "h1", text: "My Files"
    assert_no_selector "[data-controller~='room']"

    page.execute_script("window.__answer()")
    page.document.synchronize do
      stopped = evaluate_script("window.__camera.getTracks().every(track => track.readyState === 'ended')")
      raise Capybara::ExpectationNotMet, "the camera is still on" unless stopped
    end
  end

  test "a call that drops leaves nothing behind that later looks like a call" do
    visit tool_path(@tool)
    wait_for_turbo
    wait_for_stimulus "room"
    assert_selector "[data-room-target='preJoinError']", text: /camera|microphone/i, wait: 5
    start_call_without_a_server

    assert_selector "[data-room-mode-value='full'] [data-room-target='inCall']"
    assert_selector ".sidebar [data-tool-id='#{@tool.id}'][data-in-call]"

    page.execute_script("window.__dropCall()")

    # A fresh pre-join page, told why
    assert_text "You were disconnected from the call"
    assert_selector "[data-room-target='preJoin']"
    assert_no_selector "[data-room-mode-value='full']"
    assert_no_selector "[data-in-call]"
    assert_equal [ "DELETE", "remaining=1" ], evaluate_script("window.__activityPings.at(-1)")

    find(".sidebar a", text: "My Files").click
    assert_selector "h1", text: "My Files"
    assert_no_selector "#persistent-room [data-controller~='room']", visible: :all
    assert_no_selector "[data-in-call]"
  end

  test "a call that drops while in the small window takes the window away" do
    visit tool_path(@tool)
    wait_for_turbo
    wait_for_stimulus "room"
    assert_selector "[data-room-target='preJoinError']", text: /camera|microphone/i, wait: 5
    start_call_without_a_server

    find(".sidebar a", text: "My Files").click
    assert_selector "h1", text: "My Files"
    assert_selector "[data-room-mode-value='pip']"

    page.execute_script("window.__dropCall()")

    assert_text "You were disconnected from the call"
    assert_no_selector "[data-room-mode-value]", visible: :all
    assert_no_selector "[data-in-call]"
    assert_selector "h1", text: "My Files"
  end

  test "the small call window is dragged by its bar, and stops following when the touch is cancelled" do
    visit tool_path(@tool)
    wait_for_turbo
    wait_for_stimulus "room"
    assert_selector "[data-room-target='preJoinError']", text: /camera|microphone/i, wait: 5
    start_call_without_a_server
    find(".sidebar a", text: "My Files").click
    assert_selector "h1", text: "My Files"
    assert_selector "[data-room-mode-value='pip']"

    bar = "[data-room-mode-value='pip'] .tool-topbar"
    assert_equal "none", evaluate_script("getComputedStyle(document.querySelector(#{bar.to_json})).touchAction")

    drag = <<~JS
      (() => {
        const bar = document.querySelector(#{bar.to_json})
        const corner = () => { const box = bar.getBoundingClientRect(); return [Math.round(box.left), Math.round(box.top)] }
        const point = (type, target, x, y) => target.dispatchEvent(new PointerEvent(type, { bubbles: true, cancelable: true, clientX: x, clientY: y, pointerType: "touch" }))
        const [left, top] = corner()

        point("pointerdown", bar, left + 10, top + 5)
        point("pointermove", document, left - 190, top - 95)
        const dragged = corner()
        point(arguments[0], document, left - 190, top - 95)
        point("pointermove", document, left - 400, top - 300)

        return [[left - 200, top - 100], dragged, corner()]
      })()
    JS

    %w[pointerup pointercancel].each do |ending|
      expected, dragged, afterwards = page.evaluate_script(drag.sub("arguments[0]", ending.to_json))
      assert_equal expected, dragged, "the window follows the finger on its bar"
      assert_equal dragged, afterwards, "the window kept following after #{ending}"
    end
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

  # Safari kept a tile's old height when only its width changed (Chrome never did), leaving a
  # wide, flat strip. The height no longer hangs on aspect-ratio; this checks every way a tile is sized.
  test "a tile keeps its shape through the small window and a shared screen" do
    visit tool_path(@tool)
    wait_for_turbo
    wait_for_stimulus "room"

    page.execute_script(<<~JS)
      const room = window.Stimulus.getControllerForElementAndIdentifier(document.querySelector("[data-controller~='room']"), "room")
      room.preJoinTarget.classList.add("hidden")
      room.inCallTarget.classList.remove("hidden")
      room.modeValue = "pip"
      room.renderParticipant({ identity: "anna", name: "Anna" })
    JS

    # After the resize observer has had its turn
    tile = <<~JS
      const done = arguments[0]
      requestAnimationFrame(() => requestAnimationFrame(() => {
        const box = document.querySelector("[data-participant-id]").getBoundingClientRect()
        const area = document.querySelector("[data-room-target='contentArea']").getBoundingClientRect()
        done({ ratio: Math.round(box.width / box.height * 100), width: Math.round(box.width), fills: box.height >= area.height - 1 })
      }))
    JS
    mode = ->(value) { page.execute_script("document.querySelector(\"[data-controller~='room']\").dataset.roomModeValue = arguments[0]", value) }
    share = ->(on) do
      page.execute_script(<<~JS, on)
        const room = window.Stimulus.getControllerForElementAndIdentifier(document.querySelector("[data-controller~='room']"), "room")
        room.spotlightTarget.classList.toggle("hidden", !arguments[0])
        room.contentAreaTarget.toggleAttribute("data-has-spotlight", arguments[0])
      JS
    end

    assert page.evaluate_async_script(tile)["fills"], "the small window is all camera"

    mode.call("full")
    full = page.evaluate_async_script(tile)
    assert_equal 178, full["ratio"]
    assert_operator full["width"], :>, 600

    share.call(true)
    strip = page.evaluate_async_script(tile)
    assert_equal 178, strip["ratio"]
    assert_equal 224, strip["width"]

    share.call(false)
    assert_equal full, page.evaluate_async_script(tile)
  end

  test "while someone shares their screen, everyone's camera stays in view beside it" do
    visit tool_path(@tool)
    wait_for_turbo
    wait_for_stimulus "room"

    # No video server here: seat two people and put a shared screen up the way a room would
    page.execute_script(<<~JS)
      const room = window.Stimulus.getControllerForElementAndIdentifier(document.querySelector("[data-controller~='room']"), "room")
      room.preJoinTarget.classList.add("hidden")
      room.inCallTarget.classList.remove("hidden")
      room.modeValue = "full"
      ;["anna", "bo"].forEach(identity => room.renderParticipant({ identity, name: identity }))
      room._spotlightIdentity = "anna"
      room.spotlightTarget.classList.remove("hidden")
      room.contentAreaTarget.dataset.hasSpotlight = "true"
      room._updateEmptyState()
    JS

    assert_selector "[data-room-target='spotlight']"
    assert_selector "[data-participant-id='anna']"
    assert_selector "[data-participant-id='bo']"
    beside = evaluate_script(<<~JS)
      (() => {
        const screen = document.querySelector("[data-room-target='spotlight']").getBoundingClientRect()
        return [...document.querySelectorAll("[data-participant-id]")].every(tile => {
          const box = tile.getBoundingClientRect()
          return box.left >= screen.right || box.top >= screen.bottom
        })
      })()
    JS
    assert beside, "the cameras sit beside the shared screen, not under it"
  end

  private

  # No video server here: puts the page in a call the way a finished join does, with a room
  # that only knows how to drop. One other person is in it.
  def start_call_without_a_server
    page.evaluate_async_script(<<~JS)
      const done = arguments[0]
      import("livekit-client").then(({ RoomEvent, Track }) => {
        const element = document.querySelector("[data-controller~='room']")
        const controller = window.Stimulus.getControllerForElementAndIdentifier(element, "room")
        const handlers = {}
        const room = {
          state: "connected",
          remoteParticipants: new Map([["anna", { identity: "anna", name: "Anna", trackPublications: new Map() }]]),
          localParticipant: { identity: "me", trackPublications: new Map() },
          on(event, handler) { handlers[event] = handler; return this },
          disconnect: async () => {}
        }

        window.__activityPings = []
        const original = window.fetch
        window.fetch = (url, options = {}) => {
          if (String(url).includes("/activity")) window.__activityPings.push([options.method, String(url).split("?")[1] || ""])
          return original(url, options)
        }
        window.__dropCall = () => {
          room.state = "disconnected"
          room.remoteParticipants.clear()
          handlers[RoomEvent.Disconnected]()
        }

        controller._stopPreview()
        controller.room = room
        controller.LiveKitTrack = Track
        controller._bindRoomEvents(RoomEvent)
        element._liveKitRoom = room
        element._liveKitTrack = Track
        controller._pingActivity(true)
        controller._guardAgainstUnload()
        const container = document.getElementById("persistent-room")
        container.hidden = false
        container.appendChild(element)
        done()
      })
    JS
  end
end
