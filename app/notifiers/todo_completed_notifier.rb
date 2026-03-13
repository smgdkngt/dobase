# frozen_string_literal: true

class TodoCompletedNotifier < Noticed::Event
  required_params :item, :completer, :tool

  deliver_by :custom_action_cable,
    class: "Noticed::DeliveryMethods::CustomActionCable",
    stream: -> { "notifications:#{recipient.id}" },
    message: -> { notification_data }

  notification_methods do
    def message
      completer = event.params[:completer]
      item = event.params[:item]
      "#{completer&.name || 'Someone'} completed #{item&.title || 'a todo'}"
    end

    def url
      tool = event.params[:tool]
      item = event.params[:item]
      tool ? tool_todo_path(tool, item: item&.id) : root_path
    end

    def icon_name
      "check-circle"
    end

    def notification_data
      {
        id: id,
        type: "TodoCompletedNotifier",
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
