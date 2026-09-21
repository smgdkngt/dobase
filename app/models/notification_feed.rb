# frozen_string_literal: true

# The notifications list as the bell shows it: each notification with who did
# it and what they said, and a busy chat folded into one line.
#
# Five messages in the same chat are one thing to catch up on, not five, so
# unread chat messages are grouped per chat: "Marcus and Priya sent 5
# messages in Team Chat". Everything else stays one line each. The JSON API
# keeps the plain list; this is only how the page reads it.
class NotificationFeed
  # Who did it, by the parameter each notifier names them with
  ACTOR_PARAMS = %i[sender commenter mentioner assigner mover creator uploader completer invited_by].freeze
  EXCERPT_LENGTH = 120

  Entry = Data.define(:notifications, :actors, :tool, :url, :icon, :message, :excerpt, :created_at) do
    def unread? = notifications.any?(&:unread?)
    def ids = notifications.map(&:id)
    def actor = actors.first
    def grouped? = notifications.size > 1
  end

  def initialize(notifications)
    @notifications = notifications.to_a
  end

  def entries
    grouped = @notifications.select { |n| chat_message?(n) && n.unread? }.group_by { |n| params(n)[:tool]&.id }
    seen_groups = Set.new

    @notifications.filter_map do |notification|
      if chat_message?(notification) && notification.unread?
        tool_id = params(notification)[:tool]&.id
        next if seen_groups.include?(tool_id)

        seen_groups << tool_id
        group = grouped[tool_id]
        group.size > 1 ? chat_group(group) : single(notification)
      else
        single(notification)
      end
    end
  end

  private

  def single(notification)
    Entry.new(
      notifications: [ notification ],
      actors: [ actor_of(notification) ].compact,
      tool: params(notification)[:tool],
      url: notification.url,
      icon: notification.icon_name,
      message: notification.message,
      excerpt: excerpt_of(notification),
      created_at: notification.created_at
    )
  end

  def chat_group(notifications)
    actors = notifications.filter_map { |n| actor_of(n) }.uniq
    tool = params(notifications.first)[:tool]
    names = actors.map(&:first_name)
    who = names.size <= 2 ? names.to_sentence : "#{names.first(2).join(', ')} and #{names.size - 2} more"

    Entry.new(
      notifications: notifications,
      actors: actors,
      tool: tool,
      url: notifications.first.url,
      icon: notifications.first.icon_name,
      message: "#{who} sent #{notifications.size} messages in #{tool&.name || 'a chat'}",
      excerpt: excerpt_of(notifications.first),
      created_at: notifications.first.created_at
    )
  end

  def chat_message?(notification)
    notification.event&.type == "ChatMessageNotifier"
  end

  def params(notification)
    notification.event&.params || {}
  end

  def actor_of(notification)
    ACTOR_PARAMS.lazy.map { |key| params(notification)[key] }.find { |value| value.is_a?(User) }
  end

  # What was said, when there's something to quote: the chat message or the comment
  def excerpt_of(notification)
    record = params(notification)[:message] || params(notification)[:comment]
    text = record.try(:body)&.to_plain_text.to_s.squish
    text.truncate(EXCERPT_LENGTH).presence
  rescue StandardError
    nil
  end
end
