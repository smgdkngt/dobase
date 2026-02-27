# frozen_string_literal: true

class TodoAssignmentNotifier < Noticed::Event
  required_params :item, :assigner, :tool

  deliver_by :custom_action_cable,
    class: "Noticed::DeliveryMethods::CustomActionCable",
    stream: -> { "notifications:#{recipient.id}" },
    message: -> { notification_data }

  deliver_by :email,
    mailer: "NotificationMailer",
    method: :todo_assigned

  notification_methods do
    def message
      assigner = event.params[:assigner]
      item = event.params[:item]
      "#{assigner&.name || 'Someone'} assigned you to #{item&.title || 'a todo'}"
    end

    def url
      tool = event.params[:tool]
      item = event.params[:item]
      tool ? tool_todo_path(tool, item: item&.id) : root_path
    end

    def icon_name
      "check-square"
    end

    def notification_data
      {
        id: id,
        type: "TodoAssignmentNotifier",
        message: message,
        url: url,
        icon: icon_name,
        read_at: read_at,
        created_at: created_at.iso8601
      }
    end
  end
end
