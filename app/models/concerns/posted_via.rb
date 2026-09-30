# frozen_string_literal: true

# Remembers which access token posted a record. The token's owner stays the
# record's user, so rights and ownership work the same either way, but how it
# reads depends on the token:
#
# - a token that posts as its owner shows "via Claude" next to their name
# - an agent token shows under its own name, "Claude for Sem", and what it
#   posts is news to its owner too: they get notified and see it as unread
#
# The token's name is copied, so the label survives renaming or revoking it.
module PostedVia
  extend ActiveSupport::Concern

  included do
    before_create :remember_access_token

    # What someone didn't write themselves, their agent's posts included
    scope :not_written_by, ->(user) { where.not(user_id: user.id).or(where(agent: true)) }
  end

  def written_by?(user)
    user.present? && user_id == user.id && !agent?
  end

  # Who wrote it, as notifications name them: "Claude for Sem" for an agent
  def byline
    agent? ? "#{via} for #{user&.first_name || "a former member"}" : user&.name
  end

  private

  def remember_access_token
    return unless (access_token = Current.access_token)

    self.via = access_token.name
    self.agent = access_token.agent?
  end

  # Everyone to tell about it: the author never, an agent's owner always
  def notification_audience(tool)
    agent? ? tool.notifiable_users : tool.notifiable_users.where.not(id: user_id)
  end

  def author_to_skip
    user unless agent?
  end
end
