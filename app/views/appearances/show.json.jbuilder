theme = current_user.theme(scheme)

json.name theme&.name
json.label theme&.label
json.mode theme&.mode
json.custom current_user.theme_colors.present? && theme&.name == current_user.theme_name
# The palette the theme is made from, for a client that draws itself (the CLI's app)
json.colors theme&.palette&.transform_values(&:to_s)
# What a page puts on <html>: see services/theme.js
json.typeface current_user.typeface
json.merge! Theme.payload(theme, current_user.typeface).slice(:version, :style, :chrome_color)

# One theme for when the system is light and one for when it is dark, and which
json.follows_system current_user.theme_follows_system?
if current_user.theme_follows_system?
  %w[light dark].each do |slot|
    worn = current_user.theme(slot)
    json.set!(slot) { json.name worn&.name; json.label worn&.label || Rails.application.config.x.app.name }
  end
end

json.themes Theme.all do |built_in|
  json.(built_in, :name, :label, :mode)
end
