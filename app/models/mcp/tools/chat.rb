# frozen_string_literal: true

module Mcp
  module Tools
    module Chat
      extend Declaring

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
    end
  end
end
