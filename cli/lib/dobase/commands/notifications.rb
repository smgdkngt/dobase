# frozen_string_literal: true

module Dobase
  module Commands
    class Notifications < Command
      noun "notification", "Your notifications"

      command "notification list", "List your notifications, newest first (* = unread)",
        flags: {
          unread: [ nil, "Only unread notifications" ],
          limit: [ "N", "Number of notifications (default 20, max 100)" ]
        } do |unread: false, limit: nil|
        notifications = get("/notifications", unread: unread || nil, limit: limit)

        output(notifications) do
          say(unread ? "No unread notifications." : "No notifications.") if notifications.empty?
          table(notifications.map { |notification|
            [ notification["read"] ? "" : "*", notification["id"], moment(notification["created_at"]), notification["message"], notification["url"] ]
          }, indent: 0)
        end
      end

      command "notification read", "Mark a notification as read, or all of them with --all", args: %w[[ID]],
        flags: { all: [ nil, "Mark every notification as read" ] } do |id = nil, all: false|
        raise UsageError, "Give a notification ID or --all, not both." if id && all
        raise UsageError, "Give a notification ID or --all. `dobase notification list` shows the ids." unless id || all

        if all
          result = post("/notification_reads")
          output(result) { say "Marked #{count(result["marked_as_read"], "notification")} as read." }
        else
          raise UsageError, "Expected a notification id like 41, got #{quoted(id)}." unless id.match?(/\A\d+\z/)

          notification = post("/notifications/#{id}/read")
          output(notification) { say "Marked notification #{notification["id"]} as read: #{notification["message"]}" }
        end
      end
    end
  end
end
