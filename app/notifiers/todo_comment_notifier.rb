# frozen_string_literal: true

class TodoCommentNotifier < Noticed::Event
  required_params :comment, :commenter, :item, :tool

  deliver_by :custom_action_cable,
    class: "Noticed::DeliveryMethods::CustomActionCable",
    stream: -> { "notifications:#{recipient.id}" },
    message: -> { notification_data }

  notification_methods do
    def message
      commenter = event.params[:commenter]
      item = event.params[:item]
      "#{commenter&.name || 'Someone'} commented on #{item&.title || 'a todo'}"
    end

    def url
      tool = event.params[:tool]
      item = event.params[:item]
      tool ? tool_todo_path(tool, item: item&.id) : root_path
    end

    def icon_name
      "message-square-text"
    end

    def notification_data
      {
        id: id,
        type: "TodoCommentNotifier",
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
