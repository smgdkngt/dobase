# frozen_string_literal: true

class CardAssignmentNotifier < Noticed::Event
  required_params :card, :assigner, :tool

  deliver_by :custom_action_cable,
    class: "Noticed::DeliveryMethods::CustomActionCable",
    stream: -> { "notifications:#{recipient.id}" },
    message: -> { I18n.with_locale(Translation.supported(recipient.try(:locale)) || I18n.default_locale) { notification_data } }

  notification_methods do
    def message
      assigner = event.params[:assigner]
      card = event.params[:card]
      _("%{person} assigned you to %{item}", person: assigner&.name || _("Someone"), item: card&.title || _("a card"))
    end

    def url
      tool = event.params[:tool]
      card = event.params[:card]
      tool ? tool_board_path(tool, card: card&.id) : root_path
    end

    def icon_name
      "check-square"
    end

    def notification_data
      {
        id: id,
        type: "CardAssignmentNotifier",
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
