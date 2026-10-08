# frozen_string_literal: true

require "application_system_test_case"

# Pictures of the app, to lay a change beside what was there: `bin/screenshots`.
# Not a test (nothing here passes or fails on how a page looks), so `bin/rails test`
# leaves this file alone.
#
# Every scene is the example workspace the demo gives a visitor (Demo::Workspace), on
# a clock that stands still, in a window of a set size. Two runs of the same code
# give the same pictures to the pixel, so a pixel that differs is the change.
class ScreenshotScenes < ApplicationSystemTestCase
  # A Wednesday, so tomorrow and yesterday are in the same week, and in the future,
  # so a cookie the server dates from here hasn't run out for the browser
  NOW = Time.utc(2030, 1, 16, 10, 0)
  WIDE = [ 1400, 900 ].freeze
  PHONE = [ 390, 844 ].freeze
  SHOTS = Pathname.new(ENV.fetch("SHOTS", "tmp/shots/now")).expand_path(Rails.root)

  # A picture is taken once the page has come to rest: the same three times in a row,
  # half a second apart. What a page does a moment after it is there (a tool in sight
  # is said to be seen, and its dot goes) is in the picture that way.
  REST = 0.5
  SAME = 3
  TRIES = 30

  TILE = ".workspace-tile:not([hidden])"

  # What says a tool's page is all there, where `main` being there doesn't: a room
  # asks for the camera first, and headless Chrome has none
  THERE = { "Standup Room" => "[data-room-target='preJoinError']:not(.hidden)" }.freeze

  # Drawn by the processor, which draws the same thing the same way every time; the
  # graphics card rounds the edge of a letter one way now and another way then
  driven_by :selenium, using: :headless_chrome, screen_size: WIDE do |options|
    options.add_preference("profile.password_manager_leak_detection", false)
    options.add_argument("--disable-gpu")
    options.add_argument("--disable-gpu-rasterization")
    options.add_argument("--force-color-profile=srgb")
    options.add_argument("--disable-partial-raster")
    options.add_argument("--disable-skia-runtime-opts")
    options.add_argument("--run-all-compositor-stages-before-draw")
    options.add_argument("--disable-checker-imaging")
  end

  def self.scene(name, size: WIDE, scheme: "light", &block)
    test name do
      window(*size, scheme: scheme)
      instance_exec(&block)
      shoot name
    end
  end

  # The clock stops before the fixtures are read, which say "tomorrow" too
  def before_setup
    travel_to NOW
    super
  end

  setup do
    create_demo_tool_types
    @sophie = User.create!(first_name: "Sophie", last_name: "Chen", email_address: "sophie@moonshot-snacks.com", password: "password")
    Demo::Workspace.new(@sophie).build
    # A chat in sight reads its messages, and the count on the bell follows when the
    # page hears of it, which is sooner or later than the picture. So they are read.
    @sophie.notifications.joins(:event).where(noticed_events: { type: "ChatMessageNotifier" }).update_all(read_at: NOW, seen_at: NOW)
  end

  # ── The workspace: a wide window ──

  %w[Product\ Launch Team\ Chat Launch\ Tasks Launch\ Docs Team\ Files Mail Calendar Standup\ Room].each do |tool|
    scene "workspace/#{tool.parameterize}" do
      workspace tool
    end
  end

  scene "workspace/four-tiles" do
    workspace "Product Launch", "Team Chat", "Mail", "Launch Tasks"
  end

  scene "workspace/four-more-tiles" do
    workspace "Calendar", "Team Files", "Launch Docs", "Standup Room"
  end

  scene "workspace/four-tiles-dark", scheme: "dark" do
    workspace "Product Launch", "Team Chat", "Mail", "Launch Tasks"
  end

  scene "workspace/four-tiles-themed" do
    @sophie.choose_theme("tokyo-night")
    @sophie.update!(typeface: "mono")
    workspace "Product Launch", "Team Chat", "Mail", "Launch Tasks"
  end

  # Someone's first time: nothing arranged yet, so the first tool, and a line about tiles
  scene "workspace/first-visit" do
    workspace first_visit: true
  end

  scene "workspace/menu" do
    workspace "Product Launch", "Team Chat"
    find(".workspace-bar-btn[aria-label='Menu']").click
    assert_selector ".sidebar.open"
  end

  scene "workspace/menu-searching" do
    workspace "Product Launch", "Team Chat"
    find(".workspace-bar-btn[aria-label='Menu']").click
    find(".sidebar.open input[data-command-palette-target='input']").set("la")
    assert_selector ".command-palette-item.selected"
  end

  scene "workspace/document" do
    workspace page_of("Launch Docs", "docs/documents/#{document("Brand Guidelines").id}")
  end

  scene "workspace/mail-conversation" do
    workspace page_of("Mail", "mails/#{mail("Seed Round Follow-up").id}")
  end

  scene "workspace/card" do
    workspace page_of("Product Launch", "board?card=#{card("Write press release for launch day").id}")
    assert_selector "#{TILE} > .tile-frame dialog[open]"
  end

  scene "workspace/todo" do
    workspace page_of("Launch Tasks", "todo?item=#{todo("Write launch email newsletter").id}")
    assert_selector "#{TILE} > .tile-frame dialog[open]"
  end

  # ── A card's colours: the same in the app's own look and in every theme ──

  { "" => nil, "-dark" => nil, "-lumon" => "lumon", "-rose-pine" => "rose-pine", "-matte-black" => "matte-black" }.each do |look, theme|
    scheme = look == "-dark" ? "dark" : "light"

    scene "colours/board#{look}", scheme: scheme do
      six_colours
      @sophie.choose_theme(theme) if theme
      workspace "Product Launch"
    end

    scene "colours/card#{look}", scheme: scheme do
      six_colours
      @sophie.choose_theme(theme) if theme
      workspace page_of("Product Launch", "board?card=#{card("Write press release for launch day").id}")
      assert_selector "#{TILE} > .tile-frame dialog[open]"
      find("[commandfor='card-color-menu']").click
      assert_selector "#card-color-menu:popover-open"
    end
  end

  # ── One tool at a time: a phone ──

  %w[Product\ Launch Team\ Chat Launch\ Tasks Launch\ Docs Team\ Files Mail Calendar Standup\ Room].each do |tool|
    scene "phone/#{tool.parameterize}", size: PHONE do
      one_tool page_of(tool)
      assert_selector THERE.fetch(tool, "main")
    end
  end

  scene "phone/menu", size: PHONE do
    one_tool page_of("Product Launch")
    find(".mobile-bottom-bar-center").click
    assert_selector ".sidebar.open"
  end

  scene "phone/document", size: PHONE do
    one_tool page_of("Launch Docs", "docs/documents/#{document("Brand Guidelines").id}")
  end

  scene "phone/mail-conversation", size: PHONE do
    one_tool page_of("Mail", "mails/#{mail("Seed Round Follow-up").id}")
  end

  scene "phone/mail-compose", size: PHONE do
    one_tool page_of("Mail", "mails/new")
  end

  # A reply with the mail it answers opened below the text
  scene "phone/mail-reply", size: PHONE do
    one_tool page_of("Mail", "mails/new?reply_to=#{mail("Seed Round Follow-up").id}")
    find(".compose-quote-toggle").click
    within_frame(find(".compose-quote iframe")) { assert_selector "body *" }
  end

  scene "phone/card", size: PHONE do
    one_tool page_of("Product Launch", "board?card=#{card("Write press release for launch day").id}")
    assert_selector "dialog[open]"
  end

  scene "phone/todo", size: PHONE do
    one_tool page_of("Launch Tasks", "todo?item=#{todo("Write launch email newsletter").id}")
    assert_selector "dialog[open]"
  end

  scene "phone/profile", size: PHONE do
    one_tool edit_profile_path
  end

  scene "phone/product-launch-dark", size: PHONE, scheme: "dark" do
    one_tool page_of("Product Launch")
  end

  scene "phone/mail-themed", size: PHONE do
    @sophie.choose_theme("gruvbox")
    one_tool page_of("Mail")
  end

  # ── Nobody signed in ──

  scene "signed-out/sign-in" do
    visit new_session_path
    assert_selector "form"
  end

  scene "signed-out/sign-in-phone", size: PHONE do
    visit new_session_path
    assert_selector "form"
  end

  scene "signed-out/forgot-password" do
    visit new_password_path
    assert_selector "form"
  end

  private

  # ── What a scene is made of ──

  # The workspace with these tools as its tiles (by name, or the path of a page):
  # one alone, two side by side, four in a square
  def workspace(*pages, first_visit: false)
    paths = pages.map { |page| page.start_with?("/") ? page : page_of(page) }
    there = pages.map { |page| THERE.fetch(page, "main") }
    ids = paths.each_index.map { |index| "tile#{index + 1}" }
    tree = case ids
    in [] then nil
    in [ one ] then { tile: one }
    in [ one, two ] then split("row", one, two)
    in [ one, two, three, four ] then split("row", split("column", one, three), split("column", two, four))
    end
    desk = { tree: tree, focus: ids.first, alone: false, name: "" }
    state = { desk: 1, desks: { "1" => desk }, tiles: ids.zip(paths).to_h { |id, path| [ id, { url: path, title: "" } ] } }
    @sophie.create_workspace_layout!(state: state, revision: 1) unless first_visit

    sign_in(told_about_tiles: !first_visit)
    assert_selector "[data-controller~='workspace']"
    wait_for_stimulus "workspace"
    count = first_visit ? 1 : ids.size
    assert_selector "#{TILE} > :is(iframe, .tile-frame)", count: count
    count.times do |index|
      frame = all("#{TILE} > :is(iframe, .tile-frame)")[index]
      # A tile is a part of this page, or (a room) a document of its own
      next within_frame(frame) { assert_selector there[index] || "main" } if frame.tag_name == "iframe"

      within(frame) { assert_selector ".tile-page" }
    end
  end

  # A page with nothing around it but the bar at the bottom, as a narrow window has it
  def one_tool(path)
    sign_in
    visit path
    assert_selector "main"
  end

  def split(direction, first, second)
    leaf = ->(tree) { tree.is_a?(String) ? { tile: tree } : tree }
    { split: direction, ratio: 0.5, first: leaf.(first), second: leaf.(second) }
  end

  def page_of(tool_name, page = nil)
    tool = @sophie.owned_tools.find_by!(name: tool_name)
    page ? "/tools/#{tool.id}/#{page}" : tool_path(tool)
  end

  # Every colour a card can have, on the cards of the launch board
  def six_colours
    board = Boards::Board.find_by!(tool: @sophie.owned_tools.find_by!(name: "Product Launch"))
    board.columns.flat_map(&:cards).zip(BoardsHelper::CARD_COLORS.keys.cycle) { |card, color| card.update_columns(color: color) }
  end

  def card(title) = Boards::Card.find_by!(title: title)
  def todo(title) = Todos::Item.find_by!(title: title)
  def document(title) = Docs::Document.find_by!(title: title)
  def mail(subject) = Mails::Message.find_by!(subject: subject)

  # ── The browser ──

  # A window of exactly this size, in a light or a dark system, on the server's clock
  def window(width, height, scheme:)
    browser = page.driver.browser
    browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
    browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: scheme } ])
    browser.execute_cdp("Emulation.setTimezoneOverride", timezoneId: "UTC")
    @@clock ||= browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: <<~JS)
      (() => {
        const ahead = #{(NOW.to_f * 1000).to_i} - Date.now()
        const Real = Date
        window.Date = class extends Real {
          constructor(...given) { given.length ? super(...given) : super(Real.now() + ahead) }
          static now() { return Real.now() + ahead }
        }
      })()
    JS
  end

  # As it is outside the tests: a wide window works in the workspace, a narrow one
  # has one tool at a time. Nothing a scene before this one left in the browser.
  def sign_in(told_about_tiles: true)
    visit new_session_path
    page.execute_script("localStorage.clear(); sessionStorage.clear()")
    page.execute_script("localStorage.setItem('dobase:workspace:hint', 'seen')") if told_about_tiles
    fill_in "Email", with: @sophie.email_address
    fill_in "Password", with: "password"
    click_on "Sign In"
    assert_no_current_path new_session_path, wait: 15
  end

  # ── The picture ──

  def shoot(name)
    file = SHOTS.join("#{name}.png")
    file.dirname.mkpath

    pictures = []
    TRIES.times do
      hold_still
      sleep REST
      pictures << page.driver.browser.screenshot_as(:png)
      return file.binwrite(pictures.last) if pictures.size >= SAME && pictures.last(SAME).uniq.one?
    end

    file.binwrite(pictures.last)
    flunk "#{name} never came to rest: its picture kept changing"
  end

  # Whatever moves by itself is put where it ends up, in the page and in every frame
  # of it: animations and transitions are finished (one that never ends is stopped at
  # its start), and no caret blinks
  def hold_still
    page.execute_script(<<~JS)
      const pages = (frame) => {
        const found = [ frame ]
        for (const inner of frame.document.querySelectorAll("iframe")) {
          try { if (inner.contentDocument) found.push(...pages(inner.contentWindow)) } catch (error) {}
        }
        return found
      }

      for (const frame of pages(window)) {
        if (!frame.document.screenshotCalm) {
          const calm = new frame.CSSStyleSheet()
          calm.replaceSync("* { caret-color: transparent !important }")
          frame.document.adoptedStyleSheets = [ ...frame.document.adoptedStyleSheets, calm ]
          frame.document.screenshotCalm = true
        }
        for (const animation of frame.document.getAnimations()) {
          try { animation.finish() } catch (error) { animation.currentTime = 0; animation.pause() }
        }
      }
    JS
  end
end
