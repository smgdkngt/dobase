# frozen_string_literal: true

module ChatsHelper
  # A message reads as a continuation of the one above it when the same person
  # sent it on the same day, shortly after: no avatar, no name, just the line.
  def chat_continuation?(previous, message)
    return false if previous.nil?

    previous.user_id == message.user_id &&
      previous.created_at.to_date == message.created_at.to_date &&
      (message.created_at - previous.created_at) < 5.minutes
  end
end
