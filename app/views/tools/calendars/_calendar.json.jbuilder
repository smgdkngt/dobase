json.(calendar, :id, :name)
json.color calendar.color_hex
json.(calendar, :is_default, :enabled, :read_only)
# Whether new events can be added to it.
json.writable calendar.enabled? && !calendar.read_only?
