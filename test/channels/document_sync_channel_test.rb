# frozen_string_literal: true

require "test_helper"

class DocumentSyncChannelTest < ActionCable::Channel::TestCase
  setup do
    @document = docs_documents(:meeting_notes)
    @document.updates.delete_all
    DocumentPresence.reset!
    @document.update!(content: "<p>Meeting notes from Tuesday</p>")
    stub_connection current_user: users(:one)
  end

  test "the first page to arrive is handed the text to build the shared copy from" do
    subscribe document_id: @document.id

    sync = transmissions.last
    assert_equal "sync", sync["type"]
    assert_equal [], sync["updates"]
    assert_includes sync["seed"], "Meeting notes from Tuesday"
  end

  test "everyone after joins the copy that page made, and gets no text of their own" do
    subscribe document_id: @document.id
    unsubscribe
    subscribe document_id: @document.id

    assert_nil transmissions.last["seed"]
  end

  test "a change is kept and passed on" do
    subscribe document_id: @document.id
    change = Base64.strict_encode64("\x01\x02")

    assert_difference -> { @document.updates.where(seed: false).count }, 1 do
      assert_broadcast_on(DocumentSyncChannel.broadcasting_for(@document),
        type: "update", update: change, origin: "abc") do
        perform :apply_update, update: change, origin: "abc"
      end
    end
  end

  test "a change too large to be typing is refused, and only its sender hears" do
    subscribe document_id: @document.id
    change = Base64.strict_encode64("x" * 2_000)

    stub_const(DocumentSyncChannel, :MAX_UPDATE_SIZE, 1_000) do
      assert_no_difference -> { @document.updates.where(seed: false).count } do
        assert_no_broadcasts(DocumentSyncChannel.broadcasting_for(@document)) do
          perform :apply_update, update: change, origin: "abc"
        end
      end
    end

    assert_equal({ "type" => "refused", "reason" => "This change is too large to share" }, transmissions.last)
  end

  test "a document that has grown too large takes no more changes" do
    subscribe document_id: @document.id
    @document.updates.create!(data: "x" * 900)

    stub_const(DocumentSyncChannel, :MAX_DOCUMENT_SIZE, 1_000) do
      assert_no_difference -> { @document.updates.count } do
        perform :apply_update, update: Base64.strict_encode64("y" * 200), origin: "abc"
      end
    end

    assert_equal({ "type" => "refused", "reason" => "This document is too large to share more changes" }, transmissions.last)
  end

  test "a demo over its storage budget takes no more changes" do
    subscribe document_id: @document.id

    in_demo_mode do
      stub_const(Demo, :STORAGE_BUDGET, 0) do
        assert_no_difference -> { @document.updates.count } do
          perform :apply_update, update: Base64.strict_encode64("y"), origin: "abc"
        end
      end
    end

    assert_equal "The demo is full right now", transmissions.last["reason"]
  end

  test "a merged copy larger than a document may be is not kept" do
    subscribe document_id: @document.id
    @document.updates.create!(data: "\x01")

    stub_const(DocumentSyncChannel, :MAX_DOCUMENT_SIZE, 100) do
      perform :merge_updates, snapshot: Base64.strict_encode64("z" * 200)
    end

    assert_equal [ "\x01" ], @document.updates.where(seed: false).pluck(:data)
  end

  test "a caret is passed on but never kept" do
    subscribe document_id: @document.id

    assert_no_difference -> { Docs::Update.count } do
      assert_broadcast_on(DocumentSyncChannel.broadcasting_for(@document),
        type: "awareness", awareness: "AQI=", origin: "abc", hello: false) do
        perform :move_caret, awareness: "AQI=", origin: "abc"
      end
    end
  end

  test "a page that just arrived asks for everyone's caret with its own" do
    subscribe document_id: @document.id

    assert_broadcast_on(DocumentSyncChannel.broadcasting_for(@document),
      type: "awareness", awareness: "AQI=", origin: "abc", hello: true) do
      perform :move_caret, awareness: "AQI=", origin: "abc", hello: "1"
    end
  end

  test "nonsense in place of a change is dropped" do
    subscribe document_id: @document.id

    assert_no_difference -> { Docs::Update.count } do
      perform :apply_update, update: "not base64!!", origin: "abc"
    end
  end

  test "a merged copy replaces everything stored" do
    subscribe document_id: @document.id
    3.times { perform :apply_update, update: Base64.strict_encode64("\x01"), origin: "abc" }

    perform :merge_updates, snapshot: Base64.strict_encode64("\x09\x09")

    assert_equal 1, @document.updates.reload.count
    assert_equal "\x09\x09", @document.updates.first.data
  end

  test "having the document open says so, and closing it says so again" do
    subscribe document_id: @document.id

    assert_equal users(:one), @document.reload.locked_by

    unsubscribe

    assert_nil @document.reload.locked_by
  end

  test "closing one tab leaves the document open in the other" do
    subscribe document_id: @document.id
    DocumentPresence.connect(@document.id, users(:one).id) # a second tab

    unsubscribe

    assert_equal users(:one), @document.reload.locked_by
  end

  test "someone who can't reach the tool is turned away" do
    stub_connection current_user: User.create!(first_name: "Out", last_name: "Sider",
      email_address: "outsider-sync@example.com", password: "password123")

    subscribe document_id: @document.id

    assert subscription.rejected?
  end
end
