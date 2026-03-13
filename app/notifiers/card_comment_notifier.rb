# frozen_string_literal: true

class CardCommentNotifier < Noticed::Event
  required_params :comment, :commenter, :card, :tool

  deliver_by :custom_action_cable,
    class: "Noticed::DeliveryMethods::CustomActionCable",
    stream: -> { "notifications:#{recipient.id}" },
    message: -> { notification_data }

  notification_methods do
    def message
      commenter = event.params[:commenter]
      card = event.params[:card]
      "#{commenter&.name || 'Someone'} commented on #{card&.title || 'a card'}"
    end

    def url
      tool = event.params[:tool]
      card = event.params[:card]
      tool ? tool_board_path(tool, card: card&.id) : root_path
    end

    def icon_name
      "message-square-text"
    end

    def notification_data
      {
        id: id,
        type: "CardCommentNotifier",
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
