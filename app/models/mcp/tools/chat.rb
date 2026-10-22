# frozen_string_literal: true

module Mcp
  module Tools
    module Chat
      extend Declaring

      EMOJI = %w[👍 ❤️ 😂 🎉 😮 🙏 👀 ✅].freeze

      def self.message
        { tool_id: tool_id("chat"), message_id: id("The message's id", required: true) }
      end

      def self.path(call, suffix = nil)
        "/tools/#{call.arg(:tool_id)}/chat/messages/#{call.arg(:message_id)}#{suffix}"
      end

      tool "chat_list", "Read a chat",
        "A chat's latest messages, oldest first. Reading them doesn't mark them read. For older ones, pass the first " \
        "message's id as before.",
        params: {
          tool_id: tool_id("chat"),
          limit: number("How many, up to 200 (default 50)", maximum: 200),
          before: id("Messages before this one")
        }, read_only: true do
        get "/tools/#{arg(:tool_id)}/chat", limit: arg(:limit), before: arg(:before)
      end

      tool "chat_post", "Post in a chat", "Posts a message in a chat, optionally as a reply and with files.",
        params: { tool_id: tool_id("chat"), text: text("The message, plain text (or HTML with html: true)"), html: html_flag,
                  reply_to_id: id("The message this answers"), files: file_list("Files to send with it, 10 at most") } do
        attachments = files(:files)
        raise Tool::Error, "Give a text, files, or both" if attachments.empty? && arg(:text).blank?

        message = { body: arg(:text) ? rich(:text) : "", reply_to_id: arg(:reply_to_id) }.compact
        path = "/tools/#{arg(:tool_id)}/chat/messages"
        attachments.any? ? upload(path, message: message.merge(files: attachments)) : post(path, message:)
      end

      tool "chat_edit", "Edit a message", "Changes the text of one of your own messages.",
        params: message.merge(text: text("The new text, plain text (or HTML with html: true)", required: true), html: html_flag) do
        patch Chat.path(self), message: { body: rich(:text) }
      end

      tool "chat_delete", "Delete a message", "Deletes a message: your own, or anyone's in a chat you own.",
        params: message, destructive: true do
        delete Chat.path(self)
      end

      tool "chat_react", "React to a message", "Puts your emoji on a message, or takes it off with remove: true.",
        params: message.merge(emoji: choice(EMOJI, "The emoji", required: true), remove: flag("Take your emoji off again")) do
        if arg(:remove)
          delete Chat.path(self, "/reactions/#{ERB::Util.url_encode(arg(:emoji))}")
        else
          post Chat.path(self, "/reactions"), emoji: arg(:emoji)
        end
      end

      tool "chat_read", "Mark a chat read", "Marks a chat read up to its latest message, for you.",
        params: { tool_id: tool_id("chat") } do
        post "/tools/#{arg(:tool_id)}/chat/read"
      end
    end
  end
end
