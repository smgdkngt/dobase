# frozen_string_literal: true

# Who else is in this tool, and what they have open.
#
# Nothing is stored: every page that is here says so, and says it again every
# half minute. A page keeps the list it hears and forgets anyone who has gone
# quiet, so a browser that was closed mid-sentence disappears on its own. A page
# that arrives says hello, and everyone already here answers with where they
# are, which is how the newcomer learns who was already around.
class PresenceChannel < ApplicationCable::Channel
  # Enough to draw a card, a document or a todo item in the sentence "Sem is
  # looking at ..." — a type and an id, never free text from the browser.
  CONTEXT_FORMAT = /\A[a-z_]+(:\d+)?\z/

  def subscribed
    tool = Tool.find_by(id: params[:tool_id])
    reject and return unless tool&.accessible_by?(current_user)

    @tool = tool
    ToolPresence.connect(@tool.id, current_user.id)
    stream_for @tool
    transmit({ type: "welcome", user_id: current_user.id })
    broadcast(type: "here", context: nil, hello: true)
  end

  # Where this person is now: on arrival, on a heartbeat, and whenever they open
  # or close something. A hello asks everyone else to answer with their own.
  # Action Cable hands the payload only to an action that takes exactly one
  # argument, so these take theirs required.
  def announce(data)
    return unless @tool

    data = with_indifferent_access(data)
    broadcast(type: "here", context: context_from(data), hello: data[:hello].present?)
  end

  # The answer to someone else's hello. Same payload, without the question.
  def answer(data)
    return unless @tool

    broadcast(type: "here", context: context_from(with_indifferent_access(data)), hello: false)
  end

  # Someone is writing a comment on the card or todo in the context. Passed on
  # and forgotten: a page shows it for a few seconds unless it hears it again.
  def typing(data)
    return unless @tool

    context = context_from(with_indifferent_access(data))
    broadcast(type: "typing", context: context) if context
  end

  # One tab closing doesn't mean the person left; only the last one to go does.
  def unsubscribed
    return unless @tool
    return unless ToolPresence.disconnect(@tool.id, current_user.id)

    broadcast(type: "gone")
  end

  private

  def broadcast(payload)
    PresenceChannel.broadcast_to(@tool, payload.merge(tool_id: @tool.id, user: user_payload))
  end

  # The identity comes from the connection, never from the browser: a page can
  # say what it is looking at, not who is looking.
  def user_payload
    {
      id: current_user.id,
      name: current_user.name,
      initials: current_user.initials,
      avatar_url: avatar_url
    }
  end

  def avatar_url
    avatar = current_user.avatar
    return nil unless avatar.attached? && avatar.blob&.persisted?

    # Not .processed: that would resize the picture while the channel is still
    # answering someone's arrival. The link stands on its own and the picture is
    # made when a browser asks for it, as everywhere else in the app.
    Rails.application.routes.url_helpers.rails_representation_path(
      avatar.variant(resize_to_fill: [ 200, 200 ]), only_path: true
    )
  rescue StandardError
    nil
  end

  def with_indifferent_access(data)
    ActiveSupport::HashWithIndifferentAccess.new(data)
  end

  def context_from(data)
    context = data[:context].to_s
    context if context.match?(CONTEXT_FORMAT)
  end
end
