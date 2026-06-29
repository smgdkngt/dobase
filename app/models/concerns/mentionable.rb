# frozen_string_literal: true

# Parses @-mentions out of a record's rich-text body. Mentions are stored by
# the editor as <span data-id="42" class="mention">@Name</span>; ActionText
# keeps the data-id on the stored content (it is only stripped on final render).
module Mentionable
  extend ActiveSupport::Concern

  MENTION_SELECTOR = "span[data-id]"

  # Raw user ids referenced in the body. Not yet authorized — callers must
  # scope these against the tool's collaborators before notifying, otherwise a
  # crafted payload could ping arbitrary users.
  def mentioned_user_ids
    html = body&.body&.to_html
    return [] if html.blank?

    Nokogiri::HTML5.fragment(html)
      .css(MENTION_SELECTOR)
      .filter_map { |node| node["data-id"].presence }
      .uniq
      .map(&:to_i)
  end

  # Mentioned users that are safe and worth notifying: members of the tool who
  # haven't muted it, minus the optional author. Returns a User relation.
  def mentioned_users_in(tool, excluding: nil)
    ids = mentioned_user_ids
    return User.none if ids.empty?

    scope = tool.notifiable_users.where(id: ids)
    scope = scope.where.not(id: excluding.id) if excluding
    scope
  end
end
