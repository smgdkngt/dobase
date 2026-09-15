# The same payload the notifier pushes over ActionCable, with an absolute url.
data = notification.notification_data

json.id notification.id
json.type data[:type]
json.message data[:message]
json.url absolute_url(data[:url])
json.tool_id data[:tool_id]
json.read notification.read?
json.(notification, :read_at, :created_at)
