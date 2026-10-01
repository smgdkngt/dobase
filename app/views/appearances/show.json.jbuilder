theme = current_user.theme

json.name theme&.name
json.label theme&.label
json.mode theme&.mode
json.custom current_user.theme_colors.present?
# What a page puts on <html>: see services/theme.js
json.merge! Theme.payload(theme).slice(:version, :style, :chrome_color)

json.themes Theme.all do |built_in|
  json.(built_in, :name, :label, :mode)
end
