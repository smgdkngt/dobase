# frozen_string_literal: true

require "application_system_test_case"

class DocsTest < ApplicationSystemTestCase
  setup do
    @tool = tools(:my_docs)
    @document = docs_documents(:meeting_notes)
    sign_in_as users(:one)
  end

  test "text typed just before leaving the editor is saved" do
    visit edit_tool_docs_document_path(@tool, @document)
    wait_for_turbo
    wait_for_stimulus "document-editor"

    editor.send_keys(:end, " Written at the last second")
    # Leave well within the two-second autosave delay
    find(".sidebar a", text: "My Files").click
    assert_selector "h1", text: "My Files"

    assert_eventually { @document.reload.content.to_plain_text.include?("Written at the last second") }
  end

  test "typing an address in the editor's link box doesn't set off shortcuts" do
    visit edit_tool_docs_document_path(@tool, @document)
    wait_for_turbo
    wait_for_stimulus "document-editor"
    wait_for_stimulus "hotkey", "[data-hotkey='b']"
    wait_for_stimulus "keyboard-shortcuts"

    toolbar = find("rhino-editor").shadow_root
    toolbar.find("[part~='toolbar__button--link']", match: :first).click
    address = toolbar.find("input[part~='link-dialog__input']")
    # b opens the notifications and ? the list of shortcuts, outside a field
    address.send_keys("b?")

    assert_equal "b?", address.value
    assert_no_selector "dialog[open]"
    assert_no_selector "#sidebar-notifications:popover-open"

    # Cmd/Ctrl+K still opens the command palette from there
    mod = evaluate_script("navigator.platform").match?(/Mac|iP/) ? :meta : :control
    address.send_keys([ mod, "k" ])
    assert_selector "dialog[data-controller='command-palette'][open]"
  end

  test "the editor shows its own placeholder" do
    visit edit_tool_docs_document_path(@tool, docs_documents(:empty_document))
    wait_for_turbo

    assert_selector "[data-document-editor-target='editor'] .ProseMirror [data-placeholder='Start writing...']"
  end

  test "two people write in the same document at once and both see everything" do
    tool = tools(:shared_docs)
    document = docs_documents(:shared_notes)
    visit edit_tool_docs_document_path(tool, document)
    wait_for_stimulus "document-editor"
    editor.send_keys(:end, "One writes here.")

    using_session("colleague") do
      sign_in_as users(:two)
      assert_selector "aside.sidebar"
      page.execute_script("Turbo.visit('#{Rails.application.routes.url_helpers.edit_tool_docs_document_path(tools(:shared_docs), docs_documents(:shared_notes))}')")
      wait_for_stimulus "document-editor"
      # What the other one typed arrives without a reload
      assert_selector ".ProseMirror", text: "One writes here."
      editor.send_keys(:end, " Two writes here.")
    end

    assert_selector ".ProseMirror", text: "One writes here. Two writes here."
    assert_eventually { document.reload.content.to_plain_text.include?("Two writes here.") }
  end

  test "you can see where the other one is typing" do
    tool = tools(:shared_docs)
    document = docs_documents(:shared_notes)
    visit edit_tool_docs_document_path(tool, document)
    wait_for_stimulus "document-editor"

    using_session("colleague") do
      sign_in_as users(:two)
      assert_selector "aside.sidebar"
      page.execute_script("Turbo.visit('#{Rails.application.routes.url_helpers.edit_tool_docs_document_path(tools(:shared_docs), docs_documents(:shared_notes))}')")
      wait_for_stimulus "document-editor"
      editor.send_keys(:end, "Typing")
    end

    assert_selector ".collaboration-carets__caret"
    assert_selector ".collaboration-carets__label", text: users(:two).name, visible: :all
  end

  test "you see where someone already in the document is, as soon as you open it" do
    tool = tools(:shared_docs)
    document = docs_documents(:shared_notes)
    visit edit_tool_docs_document_path(tool, document)
    wait_for_stimulus "document-editor"
    editor.send_keys(:end, "Here")

    using_session("colleague") do
      sign_in_as users(:two)
      assert_selector "aside.sidebar"
      page.execute_script("Turbo.visit('#{Rails.application.routes.url_helpers.edit_tool_docs_document_path(tools(:shared_docs), docs_documents(:shared_notes))}')")
      wait_for_stimulus "document-editor"

      # Without the first one moving: well before their page's own refresh
      assert_selector ".collaboration-carets__label", text: users(:one).name, wait: 5
      # The name steps out of the way after a moment...
      assert_no_selector ".collaboration-carets__label", text: users(:one).name, wait: 6
    end

    editor.send_keys(" and there")

    # ...and shows again when they move
    using_session("colleague") do
      assert_selector ".collaboration-carets__label", text: users(:one).name
    end
  end

  test "mentioning a colleague in a document tells them" do
    tool = tools(:shared_docs)
    document = docs_documents(:shared_notes)
    visit edit_tool_docs_document_path(tool, document)
    wait_for_stimulus "document-editor"

    editor.send_keys(:end, "Over to @Us")
    find(".mention-suggestion-item", text: users(:two).name).click

    assert_selector "[data-document-editor-target='editor'] .mention", text: "@#{users(:two).name}"
    # The mention is sent from the page, after the pick; a busy machine takes its time
    assert_eventually(timeout: 10) { users(:two).notifications.reload.any? { |n| n.message == "User One mentioned you in Shared Notes" } }
  end

  test "text written through the API takes the place of what an open editor shows, and stays" do
    document = docs_documents(:shared_notes)
    open_editor document
    editor.send_keys(:end, "Typed in the editor.")
    assert_eventually { document.updates.where("length(data) > 0").exists? }

    assert_equal "200", write_through_the_api(document, "<p>Written through the API.</p>").code

    assert_selector ".ProseMirror", text: "Written through the API."
    assert_no_selector ".ProseMirror", text: "Typed in the editor."
    wait_for_stimulus "document-editor"
    editor.send_keys(:end, " And on from there.")
    assert_eventually { document.reload.content.to_plain_text == "Written through the API. And on from there." }

    # Whoever opens it next joins that text, not the remains of the copy before it
    using_session("colleague") do
      sign_in_as users(:two)
      assert_selector "aside.sidebar"
      open_editor document
      assert_selector ".ProseMirror", text: "Written through the API. And on from there."
    end
  end

  test "an editor back from being offline finds its text replaced, and shows the new one" do
    document = docs_documents(:shared_notes)
    open_editor document
    editor.send_keys(:end, "Typed in the editor.")
    assert_eventually { document.reload.content.to_plain_text == "Typed in the editor." }

    cut_the_line document
    assert_equal "200", write_through_the_api(document, "<p>Written through the API.</p>").code
    restore_the_line

    assert_selector ".ProseMirror", text: "Written through the API."
    assert_no_selector ".ProseMirror", text: "Typed in the editor."
    assert_equal "Written through the API.", document.reload.content.to_plain_text

    wait_for_stimulus "document-editor"
    editor.send_keys(:end, " And on from there.")

    using_session("colleague") do
      sign_in_as users(:two)
      assert_selector "aside.sidebar"
      open_editor document
      assert_selector ".ProseMirror", text: "Written through the API. And on from there."
    end
  end

  test "what is typed while the connection is down reaches the others when it is back" do
    document = docs_documents(:shared_notes)
    open_editor document
    editor.send_keys(:end, "Before.")

    using_session("colleague") do
      sign_in_as users(:two)
      assert_selector "aside.sidebar"
      open_editor document
      assert_selector ".ProseMirror", text: "Before."
    end

    cut_the_line document
    editor.send_keys(:end, " During.")
    assert_changes_sent
    restore_the_line
    assert_eventually { DocumentPresence.connections(document.id, users(:one).id) == 1 }
    editor.send_keys(:end, " After.")

    using_session("colleague") do
      assert_selector ".ProseMirror", text: "Before. During. After."
    end

    # And whoever opens the document later can read all of it
    using_session("latecomer") do
      sign_in_as users(:two)
      assert_selector "aside.sidebar"
      open_editor document
      assert_selector ".ProseMirror", text: "Before. During. After."
    end
  end

  test "renaming a document before its text has arrived keeps the text" do
    document = docs_documents(:shared_notes)
    document.update!(content: "<p>Notes that have to stay</p>")
    visit tool_docs_path(document.tool)
    wait_for_turbo

    cut_the_line
    open_editor document
    fill_in "Document title", with: "Renamed"
    find("body").click

    assert_eventually { document.reload.title == "Renamed" }
    assert_equal "Notes that have to stay", document.content.to_plain_text

    # Nothing can be typed over a text that isn't there yet either
    assert_selector "[data-document-editor-target='editor'][inert]"
    assert_selector "[data-document-editor-target='saveIndicator']", text: "Connecting..."

    restore_the_line
    assert_selector ".ProseMirror", text: "Notes that have to stay"
    assert_selector "[data-document-editor-target='editor']:not([inert])"
    assert_no_selector "[data-document-editor-target='saveIndicator']", text: "Connecting..."
  end

  test "the saved text still lands in an editor that takes its time starting" do
    document = docs_documents(:shared_notes)
    document.update!(content: "<p>Notes that have to stay</p>")
    visit tool_docs_path(document.tool)
    wait_for_turbo

    # As in a tab opened in the background, where timers run late
    page.execute_script(<<~JS)
      const editor = customElements.get("rhino-editor").prototype
      const start = editor.startEditor
      editor.startEditor = function () { setTimeout(() => start.call(this), 1500) }
    JS
    open_editor document

    assert_selector ".ProseMirror", text: "Notes that have to stay"
    assert_eventually { document.updates.where("length(data) > 0").exists? }
  end

  test "a pile of changes merged by a browser still holds all of them" do
    document = docs_documents(:shared_notes)

    stub_const(DocumentSyncChannel, :COMPACT_AFTER, 3) do
      open_editor document
      %w[One Two Three Four].each do |word|
        stored = document.updates.count
        editor.send_keys(:end, " #{word}")
        assert_eventually { document.updates.count > stored }
      end

      using_session("colleague") do
        sign_in_as users(:two)
        assert_selector "aside.sidebar"
        open_editor document
        assert_selector ".ProseMirror", text: "One Two Three Four"
        assert_eventually { document.updates.count == 1 }
      end
    end

    editor.send_keys(:end, " Five")

    using_session("latecomer") do
      sign_in_as users(:two)
      assert_selector "aside.sidebar"
      open_editor document
      assert_selector ".ProseMirror", text: "One Two Three Four Five"
    end
  end

  test "a document two people have open stays open when the first of them leaves" do
    document = docs_documents(:shared_notes)
    open_editor document

    using_session("colleague") do
      sign_in_as users(:two)
      assert_selector "aside.sidebar"
      open_editor document
    end
    assert_equal users(:one), document.reload.locked_by

    page.execute_script("Turbo.visit('#{tools_path}')")
    assert_current_path tools_path

    assert_eventually { document.reload.locked_by == users(:two) }
    assert_equal "409", write_through_the_api(document, "<p>Written through the API.</p>").code

    using_session("colleague") do
      page.execute_script("Turbo.visit('#{tools_path}')")
      assert_current_path tools_path
    end

    assert_eventually { document.reload.locked_by.nil? }
  end

  test "a page with the document open says so without anything being typed" do
    document = docs_documents(:shared_notes)
    open_editor document
    assert_eventually { document.reload.locked_by == users(:one) }

    stub_const(DocumentSyncChannel, :HOLD_EVERY, 0.seconds) do
      # As after five minutes without a word from the page
      document.update_columns(locked_by_id: nil, locked_at: nil)
      # What the page does every minute
      page.execute_script(<<~JS)
        const element = document.querySelector("[data-controller~='document-editor']")
        window.Stimulus.getControllerForElementAndIdentifier(element, "document-editor").sync.send("still_here")
      JS

      assert_eventually { document.reload.locked_by == users(:one) }
    end
  end

  private

  # The editor can't be typed in until the shared copy has arrived
  def editor
    find("[data-document-editor-target='editor']:not([inert]) .ProseMirror")
  end

  # Turbo.visit, not Capybara's: a fresh page load leaves the old socket to time
  # out, and starts a new JavaScript world without the line that was cut
  def open_editor(document)
    path = edit_tool_docs_document_path(document.tool, document)
    if page.current_path.blank?
      visit path
    else
      page.execute_script("Turbo.visit('#{path}')")
    end
    assert_current_path path
    wait_for_stimulus "document-editor"
  end

  # As users(:one), whose own editor doesn't stop the write. Returns the response.
  def write_through_the_api(document, content)
    token = users(:one).access_tokens.create!(name: "Test token", permission: "write").token
    uri = URI.join(page.server.base_url, tool_docs_document_path(document.tool, document))

    Net::HTTP.start(uri.host, uri.port) do |http|
      http.patch(uri.path, { docs_document: { content: content } }.to_json,
        "Authorization" => "Bearer #{token}", "Content-Type" => "application/json", "Accept" => "application/json")
    end
  end

  # The page's Action Cable connection, closed and kept from coming back by
  # itself: a laptop asleep, a network that went away. With a document, waits
  # until the server has noticed.
  def cut_the_line(document = nil)
    with_the_line("consumer.connection.open = () => false; consumer.connection.close({ allowReconnect: false })")
    assert_eventually { DocumentPresence.connections(document.id, users(:one).id).zero? } if document
  end

  def restore_the_line
    with_the_line("delete consumer.connection.open; consumer.connection.open()")
  end

  # Changes leave a few at a time (see document_sync.js): waits until none are
  # left waiting, whether or not there was a line for them to leave on
  def assert_changes_sent
    assert_eventually do
      page.evaluate_script(<<~JS)
        (() => {
          const element = document.querySelector("[data-controller~='document-editor']")
          return window.Stimulus.getControllerForElementAndIdentifier(element, "document-editor").sync.pending.length === 0
        })()
      JS
    end
  end

  def with_the_line(script)
    page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      import("channels/consumer").then(({ default: consumer }) => { #{script}; done() })
    JS
  end

  def assert_eventually(timeout: 5)
    deadline = Time.current + timeout
    sleep 0.1 until yield || Time.current > deadline
    assert yield, "condition wasn't met within #{timeout} seconds"
  end
end
