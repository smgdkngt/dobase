# frozen_string_literal: true

module Dobase
  module Commands
    class Chat < Command
      noun "chat", "Messages in a chat (chat tools)"

      command "chat list", "Show the latest messages in a chat, oldest first (doesn't mark it read)", args: %w[TOOL],
        flags: {
          limit: [ "N", "Number of messages (default 50, max 200)" ],
          before: [ "ID", "Only messages older than this message, to page back" ]
        } do |ref, limit: nil, before: nil|
        chat_tool = tool(ref, "chat")
        chat = get("/tools/#{chat_tool["id"]}/chat", limit: limit, before: before && message_id(before))

        output(chat) do
          say "#{chat_tool["name"]} (chat #{chat_tool["id"]}) #{chat["url"]}"
          say "  (no messages)" if chat["messages"].empty?
          say "  Older messages: dobase chat list #{chat_tool["id"]} --before #{chat["messages"].first["id"]}#{" --limit #{limit}" if limit}" if chat["has_more"]

          chat["messages"].each do |message|
            say
            say "#{message.dig("user", "name")} · #{moment(message["created_at"])}#{" (edited)" if message["edited_at"]} [message #{chat_tool["id"]}/#{message["id"]}]"
            say "  > #{message.dig("reply_to", "user_name")}: #{message.dig("reply_to", "preview")}" if message["reply_to"]
            paragraph message["body"]
            message["files"].each { |file| say "  File: #{file["filename"]} (#{bytes(file["byte_size"])}) #{file["download_url"]}" }
          end
        end
      end

      command "chat post", "Send a message to a chat", args: %w[TOOL TEXT],
        flags: { html: [ nil, "TEXT is HTML" ], reply_to: [ "ID", "Reply to this message" ] } do |ref, body, html: false, reply_to: nil|
        chat_tool = tool(ref, "chat")
        attributes = { body: rich_text(body, html: html), reply_to_id: reply_to && message_id(reply_to) }.compact

        message = post("/tools/#{chat_tool["id"]}/chat/messages", message: attributes)
        output(message) { say "Posted message #{chat_tool["id"]}/#{message["id"]} to #{chat_tool["name"]}." }
      end

      command "chat edit", "Change the text of one of your messages", args: %w[TOOL/MESSAGE TEXT],
        flags: { html: [ nil, "TEXT is HTML" ] } do |ref, body, html: false|
        chat_tool, id = tool_and_id(ref, "chat", "message")
        message = patch("/tools/#{chat_tool["id"]}/chat/messages/#{id}", message: { body: rich_text(body, html: html) })
        output(message) { say "Edited message #{chat_tool["id"]}/#{message["id"]}." }
      end

      command "chat delete", "Delete a message (your own, or anyone's if you own the chat)", args: %w[TOOL/MESSAGE] do |ref|
        chat_tool, id = tool_and_id(ref, "chat", "message")
        delete("/tools/#{chat_tool["id"]}/chat/messages/#{id}")
        output(nil) { say "Deleted message #{chat_tool["id"]}/#{id}." }
      end

      command "chat read", "Mark a chat as read up to its latest message", args: %w[TOOL] do |ref|
        chat_tool = tool(ref, "chat")
        receipt = post("/tools/#{chat_tool["id"]}/chat/read")
        output(receipt) { say "Marked #{chat_tool["name"]} as read." }
      end

      private

      # A message id, or a TOOL/MESSAGE reference as printed by `chat list`.
      def message_id(value)
        id = value.to_s.split("/").last.to_s
        raise UsageError, "Expected a message id like 104, got #{quoted(value)}." unless id.match?(/\A\d+\z/)

        id
      end
    end
  end
end
