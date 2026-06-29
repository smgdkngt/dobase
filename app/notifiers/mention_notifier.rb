# frozen_string_literal: true

class MentionNotifier < Noticed::Event
  required_params :mentioner, :tool, :url, :context

  deliver_by :custom_action_cable,
    class: "Noticed::DeliveryMethods::CustomActionCable",
    stream: -> { "notifications:#{recipient.id}" },
    message: -> { notification_data }

  notification_methods do
    def message
      mentioner = event.params[:mentioner]
      context = event.params[:context]
      "#{mentioner&.name || 'Someone'} mentioned you in #{context || 'a message'}"
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
