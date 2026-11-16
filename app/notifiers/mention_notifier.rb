# frozen_string_literal: true

class MentionNotifier < Noticed::Event
  # Optional: byline, when an agent did the mentioning ("Claude for Sem"), and what
  # the mention is in: `message` (a chat message) or `comment` (on a card or a todo),
  # whose words the bell and the digest quote, and `card`, `item` or `document`, which
  # opening reads it by. Any of them can have been deleted since, and reads as nil.
  required_params :mentioner, :tool, :url, :context

  deliver_by :custom_action_cable,
    class: "Noticed::DeliveryMethods::CustomActionCable",
    stream: -> { "notifications:#{recipient.id}" },
    message: -> { notification_data }

  notification_methods do
    def message
      mentioner = event.params[:mentioner]
      context = event.params[:context]
      "#{event.params[:byline] || mentioner&.name || 'Someone'} mentioned you in #{context || 'a message'}"
    end

    def url
      event.params[:url].presence || root_path
    end

    def icon_name
      "at-sign"
    end

    def notification_data
      {
        id: id,
        type: "MentionNotifier",
        tool_id: event.params[:tool]&.id,
        message: message,
        url: url,
        icon: icon_name,
        read_at: read_at,
        created_at: created_at.iso8601
      }
    end
  end
end
