json.tool do
  json.partial! "tools/tool", tool: @tool
end
json.url tool_calendar_url(@tool, week_start: @start_date.beginning_of_week(:monday))
json.local @calendar_account.local?
json.sync do
  json.status @calendar_account.sync_status
  json.last_synced_at @calendar_account.last_synced_at
end
json.start_date @start_date
json.end_date @end_date

calendars = @calendar_account.calendars.by_position.to_a
json.calendars calendars, partial: "tools/calendars/calendar", as: :calendar

# Occurrences of recurring events are unsaved copies without loaded associations,
# so look calendars and creators up once instead of per event.
calendars_by_id = calendars.index_by(&:id)
creators_by_id = User.where(id: @events.filter_map(&:created_by_id).uniq).index_by(&:id)

json.events @events do |event|
  json.partial! "tools/calendars/events/event", event: event, tool: @tool,
    calendar: calendars_by_id[event.calendar_id], creator: creators_by_id[event.created_by_id]
end
