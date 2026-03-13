# frozen_string_literal: true

class ChatMessageNotifier < Noticed::Event
  required_params :message, :sender, :tool

  deliver_by :custom_action_cable,
    class: "Noticed::DeliveryMethods::CustomActionCable",
    stream: -> { "notifications:#{recipient.id}" },
    message: -> { notification_data }

  notification_methods do
    def message
      sender = event.params[:sender]
      tool = event.params[:tool]
      "#{sender&.name || 'Someone'} sent a message in #{tool&.name || 'a chat'}"
    end

    def url
      tool = event.params[:tool]
      tool ? tool_chat_path(tool) : root_path
    end

    def icon_name
      "message-circle"
    end

    def notification_data
      {
        id: id,
        type: "ChatMessageNotifier",
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
