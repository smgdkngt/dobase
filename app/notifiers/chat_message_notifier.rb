# frozen_string_literal: true

class ChatMessageNotifier < Noticed::Event
  required_params :message, :sender, :tool

  deliver_by :custom_action_cable,
    class: "Noticed::DeliveryMethods::CustomActionCable",
    stream: -> { "notifications:#{recipient.id}" },
    message: -> { I18n.with_locale(Translation.supported(recipient.try(:locale)) || I18n.default_locale) { notification_data } }

  notification_methods do
    def message
      sender = event.params[:sender]
      tool = event.params[:tool]
      _("%{person} sent a message in %{chat}", person: event.params[:message].try(:byline) || sender&.name || _("Someone"), chat: tool&.name || _("a chat"))
    end

    def url
      tool = event.params[:tool]
      return root_path unless tool

      # At the message itself, while it is there
      message = event.params[:message]
      tool_chat_path(tool, message: (message.id if message.is_a?(Chats::Message)))
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
