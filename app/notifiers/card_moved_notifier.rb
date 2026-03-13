# frozen_string_literal: true

class CardMovedNotifier < Noticed::Event
  required_params :card, :mover, :tool, :column

  deliver_by :custom_action_cable,
    class: "Noticed::DeliveryMethods::CustomActionCable",
    stream: -> { "notifications:#{recipient.id}" },
    message: -> { notification_data }

  notification_methods do
    def message
      mover = event.params[:mover]
      card = event.params[:card]
      column = event.params[:column]
      "#{mover&.name || 'Someone'} moved #{card&.title || 'a card'} to #{column&.name || 'a column'}"
    end

    def url
      tool = event.params[:tool]
      card = event.params[:card]
      tool ? tool_board_path(tool, card: card&.id) : root_path
    end

    def icon_name
      "arrow-right"
    end

    def notification_data
      {
        id: id,
        type: "CardMovedNotifier",
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
