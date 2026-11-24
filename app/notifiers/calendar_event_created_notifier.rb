# frozen_string_literal: true

class CalendarEventCreatedNotifier < Noticed::Event
  required_params :event, :creator, :tool

  deliver_by :custom_action_cable,
    class: "Noticed::DeliveryMethods::CustomActionCable",
    stream: -> { "notifications:#{recipient.id}" },
    message: -> { I18n.with_locale(Translation.supported(recipient.try(:locale)) || I18n.default_locale) { notification_data } }

  notification_methods do
    def message
      creator = event.params[:creator]
      cal_event = event.params[:event]
      date = cal_event&.first_day ? ApplicationController.helpers.format_date(cal_event.first_day) : _("a date")
      _("%{person} created %{event} on %{date}", person: creator&.name || _("Someone"), event: cal_event&.summary || _("an event"), date: date)
    end

    def url
      tool = event.params[:tool]
      tool ? tool_calendar_path(tool) : root_path
    end

    def icon_name
      "calendar-plus"
    end

    def notification_data
      {
        id: id,
        type: "CalendarEventCreatedNotifier",
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
