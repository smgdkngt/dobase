# frozen_string_literal: true

class ToolInvitationNotifier < Noticed::Event
  required_params :invitation, :tool, :invited_by, :recipient_user

  # Email is sent directly by CollaboratorsController, so only ActionCable here
  deliver_by :custom_action_cable,
    class: "Noticed::DeliveryMethods::CustomActionCable",
    stream: -> { "notifications:#{recipient.id}" },
    message: -> { notification_data }

  notification_methods do
    def message
      inviter = event.params[:invited_by]
      tool = event.params[:tool]
      "#{inviter&.name || 'Someone'} invited you to collaborate on #{tool&.name || 'a tool'}"
    end

    def url
      invitation = event.params[:invitation]
      invitation ? invitation_acceptance_path(token: invitation.token) : root_path
    end

    def icon_name
      "users"
    end

    def notification_data
      {
        id: id,
        type: "ToolInvitationNotifier",
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
