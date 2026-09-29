# frozen_string_literal: true

# Mail from the compose page that the mail server didn't take. It's kept as a draft.
class MailNotSentNotifier < Noticed::Event
  required_params :draft, :error, :tool

  deliver_by :custom_action_cable,
    class: "Noticed::DeliveryMethods::CustomActionCable",
    stream: -> { "notifications:#{recipient.id}" },
    message: -> { notification_data }

  notification_methods do
    def message
      subject = event.params[:draft]&.subject.presence || "(No subject)"
      "Couldn't send “#{subject}”, it's in your drafts: #{event.params[:error]}"
    end

    def url
      tool = event.params[:tool]
      draft = event.params[:draft]
      return root_path unless tool

      draft ? new_tool_mail_path(tool, draft_id: draft.id) : tool_mails_path(tool, folder: "drafts")
    end

    def icon_name
      "alert-circle"
    end

    def notification_data
      {
        id: id,
        type: "MailNotSentNotifier",
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
