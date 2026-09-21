# frozen_string_literal: true

require "test_helper"

class UserReadNotificationsTest < ActiveSupport::TestCase
  setup do
    @reader = users(:one)
    @commenter = users(:two)
    @tool = tools(:project_board)
    @tool.collaborators.find_or_create_by!(user: @commenter) { |c| c.role = "collaborator" }
  end

  test "opening a card reads what was said on it, and nothing about other cards" do
    notify_comment(cards(:first_task))
    notify_comment(cards(:second_task))

    @reader.read_notifications_about!(records: [ cards(:first_task) ])

    assert_equal [ cards(:second_task) ], @reader.notifications.unread.map { |n| n.event.params[:card] }
  end

  test "a mention is read by the page it points at" do
    MentionNotifier.with(mentioner: @commenter, tool: @tool, context: "a card", url: "/tools/#{@tool.id}/board?card=7").deliver(@reader)
    MentionNotifier.with(mentioner: @commenter, tool: @tool, context: "a card", url: "/tools/#{@tool.id}/board?card=70").deliver(@reader)

    @reader.read_notifications_about!(urls: [ "/tools/#{@tool.id}/board?card=7" ])

    assert_equal [ "/tools/#{@tool.id}/board?card=70" ], @reader.notifications.unread.map(&:url)
  end

  test "the bells on every open page are told the new count" do
    notify_comment(cards(:first_task))

    assert_broadcast_on("notifications:#{@reader.id}", type: "unread_count", count: 0) do
      @reader.read_notifications_about!(records: [ cards(:first_task) ])
    end
  end

  test "reading nothing says nothing" do
    assert_no_broadcasts("notifications:#{@reader.id}") do
      @reader.read_notifications_about!(records: [ cards(:first_task) ])
    end
  end

  private

  include ActionCable::TestHelper

  def notify_comment(card)
    comment = Boards::Comment.new(card: card, user: @commenter, body: "<p>On #{card.title}</p>")
    comment.save!
    CardCommentNotifier.with(comment: comment, commenter: @commenter, card: card, tool: @tool).deliver(@reader) unless
      @reader.notifications.unread.any? { |n| n.event.params[:card] == card }
  end
end
