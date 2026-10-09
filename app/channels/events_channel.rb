# frozen_string_literal: true

# Says that there is a new event, and nothing more: `{ id: 812 }`. Whoever hears
# it asks GET /events for what happened, which checks the token and the tools it
# may see, as any request does. So nothing that is in a tool goes over this line,
# and someone taken off a tool hears at most a number.
#
# This is the one channel a connection made with an access token may open: it is
# what `dobase events --follow` listens to between its requests.
class EventsChannel < ApplicationCable::Channel
  allow_access_tokens

  # A token that is deleted closes its connections itself (AccessToken). One that
  # went another way (its owner's account deleted) is found out here.
  periodically :close_without_token, every: 1.minute

  def self.stream_name(user_id)
    "events:#{user_id}"
  end

  def subscribed
    stream_from self.class.stream_name(current_user.id)
  end

  private
    def close_without_token
      return if access_token.nil? || AccessToken.exists?(access_token.id)

      connection.close(reason: ActionCable::INTERNAL[:disconnect_reasons][:unauthorized], reconnect: false)
    end
end
