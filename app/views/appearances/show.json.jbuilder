theme = current_user.theme

json.name theme&.name
json.label theme&.label
json.mode theme&.mode
json.custom current_user.theme_colors.present?
# The palette the theme is made from, for a client that draws itself (the CLI's app)
json.colors theme&.palette&.transform_values(&:to_s)
# What a page puts on <html>: see services/theme.js
json.typeface current_user.typeface
json.merge! Theme.payload(theme, current_user.typeface).slice(:version, :style, :chrome_color)

json.themes Theme.all do |built_in|
  json.(built_in, :name, :label, :mode)
end
