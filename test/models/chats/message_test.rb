# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

module Chats
  class MessageTest < ActiveSupport::TestCase
    include Turbo::Broadcastable::TestHelper

    setup do
      @user = users(:one)
      chat_type = ToolType.find_or_create_by!(slug: "chat") { |type| type.name = "Chat"; type.icon = "message-circle"; type.enabled = true }
      @chat = Tool.create!(name: "Team Chat", tool_type: chat_type, owner: @user).chat
    end

    test "a message right after one by the same person continues it" do
      first = @chat.messages.create!(user: @user, body: "<p>One</p>")
      second = @chat.messages.create!(user: @user, body: "<p>Two</p>")

      assert_not first.continuation?
      assert second.continuation?
    end

    test "a message after someone else's, or much later, starts a new group" do
      @chat.tool.collaborators.create!(user: users(:two), role: "collaborator")
      @chat.messages.create!(user: @user, body: "<p>One</p>", created_at: 10.minutes.ago)
      later = @chat.messages.create!(user: @user, body: "<p>Two</p>")
      theirs = @chat.messages.create!(user: users(:two), body: "<p>Three</p>")

      assert_not later.continuation?
      assert_not theirs.continuation?
    end

    test "a new message in a run arrives without its author's name again" do
      @chat.messages.create!(user: @user, body: "<p>One</p>")

      streams = capture_turbo_stream_broadcasts(@chat) { @chat.messages.create!(user: @user, body: "<p>Two</p>") }

      assert_equal "append", streams.sole["action"]
      assert continuation?(streams.sole)
    end

    test "the first message of a run arrives with its author's name" do
      streams = capture_turbo_stream_broadcasts(@chat) { @chat.messages.create!(user: @user, body: "<p>One</p>") }

      assert_not continuation?(streams.sole)
    end

    test "editing a message in the middle of a run keeps it a continuation for everyone" do
      @chat.messages.create!(user: @user, body: "<p>One</p>")
      second = @chat.messages.create!(user: @user, body: "<p>Two</p>")

      streams = capture_turbo_stream_broadcasts(@chat) { second.update!(body: "<p>Two, fixed</p>", edited_at: Time.current) }

      assert_equal "replace", streams.sole["action"]
      assert continuation?(streams.sole)
    end

    test "editing the first message of a run keeps its author's name" do
      first = @chat.messages.create!(user: @user, body: "<p>One</p>")
      @chat.messages.create!(user: @user, body: "<p>Two</p>")

      streams = capture_turbo_stream_broadcasts(@chat) { first.update!(body: "<p>One, fixed</p>", edited_at: Time.current) }

      assert_not continuation?(streams.sole)
    end

    # A broadcast is rendered once, in the zone of whoever caused it, for
    # everyone in the chat: the time has to be one the browser can redraw.
    test "an older message that is edited says when in a time the browser redraws" do
      old = @chat.messages.create!(user: @user, body: "<p>Last week</p>", created_at: 6.days.ago)
      yesterday = @chat.messages.create!(user: @user, body: "<p>Yesterday</p>", created_at: 30.hours.ago)

      [ old, yesterday ].each do |message|
        stream = capture_turbo_stream_broadcasts(@chat) { message.update!(body: "<p>Fixed</p>", edited_at: Time.current) }.sole

        time = Nokogiri::HTML5.fragment(stream.at("template").inner_html).at_css("time[data-controller='local-time']")
        assert_equal message.created_at.utc.iso8601, time["datetime"]
      end
    end

    private

    # A continuation has no header; it shows its time, without AM or PM, on hover instead
    def continuation?(stream)
      message = Nokogiri::HTML5.fragment(stream.at("template").inner_html)
      message.at_css("time[data-local-time-period-value='false']").present?
    end
  end
end
