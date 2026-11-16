# frozen_string_literal: true

require "test_helper"

# How much someone wants to hear (User#notification_level), and what a mention says
# about where it was made.
class NotificationLevelTest < ActiveSupport::TestCase
  setup do
    @reader = users(:one)
    @writer = users(:two)
    chat_type = ToolType.find_by(slug: "chat") || ToolType.create!(slug: "chat", name: "Chat", icon: "message-circle")
    @chat_tool = Tool.create!(name: "Team Chat", tool_type: chat_type, owner: @reader)
    @chat_tool.collaborators.create!(user: @writer, role: "collaborator")
  end

  test "everything reaches someone who wants everything" do
    post("Morning all")
    post("Hey #{mention(@reader)}")

    assert_equal %w[ChatMessageNotifier MentionNotifier], kinds
  end

  test "mentions and assignments leave out the rest" do
    @reader.update!(notification_level: "mentions")

    post("Morning all")
    post("Hey #{mention(@reader)}")
    card = boards(:shared).columns.create!(name: "Doing", position: 0).cards.create!(title: "Label", position: 0)
    CardAssignmentNotifier.with(card: card, assigner: @writer, tool: tools(:shared_board)).deliver(@reader)

    assert_equal %w[CardAssignmentNotifier MentionNotifier], kinds
  end

  test "nothing is nothing, but a mail that wasn't sent is still said" do
    @reader.update!(notification_level: "nothing")

    post("Hey #{mention(@reader)}")
    MailNotSentNotifier.with(draft: nil, error: "Refused", tool: @chat_tool).deliver(@reader)

    assert_equal %w[MailNotSentNotifier], kinds
  end

  test "someone else in the same delivery still gets theirs" do
    third = User.create!(first_name: "Third", last_name: "Person", email_address: "third@example.com", password: "password123")
    @chat_tool.collaborators.create!(user: third, role: "collaborator")
    @reader.update!(notification_level: "nothing")

    post("Morning all")

    assert_empty kinds
    assert_equal 1, third.notifications.count
  end

  test "a level that isn't one is refused" do
    assert_not @reader.update(notification_level: "loud")
  end

  test "a mention in a chat message keeps the message and leads to it" do
    message = post("Hey #{mention(@reader)}, the label")

    params = mention_event.params
    assert_equal message, params[:message]
    assert_equal "/tools/#{@chat_tool.id}/chat?message=#{message.id}", @reader.notifications.joins(:event).find_by(noticed_events: { type: "MentionNotifier" }).url
  end

  test "a mention in a card comment keeps the comment and the card" do
    tool = tools(:shared_board)
    card = boards(:shared).columns.create!(name: "Doing", position: 0).cards.create!(title: "Label", position: 0)
    comment = Boards::Comment.create!(card: card, user: @writer, body: "<p>#{mention(@reader)} look</p>")

    params = mention_event.params
    assert_equal comment, params[:comment]
    assert_equal card, params[:card]
    assert_equal "/tools/#{tool.id}/board?card=#{card.id}", params[:url]
  end

  test "a mention whose message was deleted still reads" do
    post("Hey #{mention(@reader)}").destroy!

    notification = @reader.notifications.joins(:event).find_by(noticed_events: { type: "MentionNotifier" })
    assert_equal "#{@writer.name} mentioned you in a chat message", notification.message
    assert_nil notification.event.params[:message]
  end

  private

  def post(html)
    @chat_tool.chat.messages.create!(user: @writer, body: "<p>#{html}</p>")
  end

  def mention(user)
    %(<span data-id="#{user.id}" class="mention">@#{user.first_name}</span>)
  end

  def kinds
    @reader.notifications.joins(:event).pluck("noticed_events.type").sort
  end

  def mention_event
    @reader.notifications.joins(:event).find_by!(noticed_events: { type: "MentionNotifier" }).event
  end
end
