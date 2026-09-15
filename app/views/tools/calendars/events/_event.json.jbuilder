# Pass `calendar` and `creator` when rendering many events to avoid a query per event.
calendar = local_assigns.fetch(:calendar) { event.calendar }
creator = local_assigns.fetch(:creator) { event.created_by }

json.(event, :id, :summary, :description, :location, :starts_at, :ends_at)
json.all_day event.all_day?
json.status event.status
json.calendar do
  json.(calendar, :id, :name)
  json.color calendar.color_hex
end
json.recurring event.is_recurring?
json.occurrence event.occurrence?
json.recurrence event.recurrence_description
json.rrule event.rrule

if event.organizer_email.present? || event.organizer_name.present?
  json.organizer do
    json.name event.organizer_name
    json.email event.organizer_email
  end
else
  json.organizer nil
end

json.attendees event.attendees do |attendee|
  json.name attendee["name"]
  json.email attendee["email"]
  json.status attendee["status"]
end

json.partial! "users/optional_user", key: "creator", user: creator
json.url tool_calendar_url(tool, week_start: event.starts_at.to_date.beginning_of_week(:monday))
