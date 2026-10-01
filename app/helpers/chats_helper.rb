# frozen_string_literal: true

module ChatsHelper
  # A message reads as a continuation of the one above it when the same person
  # sent it on the same day, shortly after: no avatar, no name, just the line.
  def chat_continuation?(previous, message)
    message.continues?(previous)
  end
end
