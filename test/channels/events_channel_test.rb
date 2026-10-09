# frozen_string_literal: true

require "test_helper"

class EventsChannelTest < ActionCable::Channel::TestCase
  setup do
    @user = users(:one)
    @token = @user.access_tokens.create!(name: "Listener")
  end

  test "a token's connection hears that there is something for its owner" do
    stub_connection current_user: @user, access_token: @token

    subscribe

    assert subscription.confirmed?
    assert_has_stream EventsChannel.stream_name(@user.id)
    assert_equal 1, subscription.streams.size
  end

  test "a page's connection may listen too" do
    stub_connection current_user: @user

    subscribe

    assert subscription.confirmed?
    assert_has_stream EventsChannel.stream_name(@user.id)
  end

  # A channel's public methods are what a connection can call on it
  test "it takes nothing from whoever listens, and no channel lets itself be opened up" do
    assert_equal %w[subscribed], EventsChannel.action_methods.to_a
    every_channel.each do |channel|
      assert_empty channel.action_methods.grep(/access_token/), "#{channel} can be told to let tokens in"
    end
  end

  # The channels of the app's pages carry what is in a chat, a document and a tool.
  # A token opens none of them, whatever it asks for and whoever its owner is: not
  # the app's own, and not the ones a gem brings, which don't inherit from the app's.
  test "a token's connection opens no other channel" do
    channels = every_channel - [ EventsChannel ]
    assert_operator channels.size, :>=, 9, "the app's channels weren't found"
    assert_includes channels, Turbo::StreamsChannel

    channels.each do |channel|
      assert_not channel.access_tokens_allowed, "#{channel} lets access tokens in"

      self.class.tests channel
      stub_connection current_user: @user, access_token: @token
      subscribe tool_id: tools(:shared_board).id, document_id: 1, id: 1,
        signed_stream_name: Turbo::StreamsChannel.signed_stream_name(tools(:shared_board))

      assert subscription.rejected?, "#{channel} let a token's connection in"
      assert_empty subscription.streams, "#{channel} streams to a token's connection"
    end
  ensure
    self.class.tests EventsChannel
  end

  # What a chat's page listens to for its messages: the name is in the page, which a
  # token may ask for
  test "a token's connection doesn't get a chat's messages with the name from its page" do
    name = Turbo::StreamsChannel.signed_stream_name(tools(:shared_board))
    self.class.tests Turbo::StreamsChannel

    stub_connection current_user: @user
    subscribe signed_stream_name: name
    assert subscription.confirmed?, "a page's connection should still get them"

    stub_connection current_user: @user, access_token: @token
    subscribe signed_stream_name: name
    assert subscription.rejected?
    assert_empty subscription.streams
  ensure
    self.class.tests EventsChannel
  end

  test "a channel that refuses a token doesn't start on what it does for a page" do
    started = []
    channel = Class.new(ApplicationCable::Channel) { define_method(:subscribed) { started << current_user } }
    self.class.tests channel

    stub_connection current_user: @user, access_token: @token
    subscribe
    assert subscription.rejected?
    assert_empty started

    stub_connection current_user: @user
    subscribe
    assert_equal [ @user ], started
  ensure
    self.class.tests EventsChannel
  end

  test "a token that is gone without saying so is found out, and the connection closed" do
    stub_connection current_user: @user, access_token: @token
    subscribe
    closed = nil
    connection.define_singleton_method(:close) { |**options| closed = options }

    subscription.send(:close_without_token)
    assert_nil closed

    AccessToken.where(id: @token.id).delete_all
    subscription.send(:close_without_token)
    assert_equal({ reason: "unauthorized", reconnect: false }, closed)
  end

  private
    # Every channel there is, the ones of gems too (and none that a test made)
    def every_channel
      Rails.application.eager_load!
      ActionCable::Channel::Base.descendants.select(&:name)
    end
end
