# frozen_string_literal: true

class CalendarEventCreatedNotifier < Noticed::Event
  required_params :event, :creator, :tool

  deliver_by :custom_action_cable,
    class: "Noticed::DeliveryMethods::CustomActionCable",
    stream: -> { "notifications:#{recipient.id}" },
    message: -> { notification_data }

  notification_methods do
    def message
      creator = event.params[:creator]
      cal_event = event.params[:event]
      date = cal_event&.start_time&.strftime("%b %-d") || "a date"
      "#{creator&.name || 'Someone'} created #{cal_event&.title || 'an event'} on #{date}"
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
