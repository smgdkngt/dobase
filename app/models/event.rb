# frozen_string_literal: true

# Something that happened in a tool: mail came in, a card moved, someone wrote in a
# chat. One row each, read from outside the browser by number ("everything after
# N", EventsController), which is what `dobase events --follow` prints a line of.
#
# An event says what happened and to what, in a few words: a title, a column, who
# wrote and what a mail is called. Never the text of a mail. Whoever wants more
# asks for the thing itself, and is answered by what they may see then.
#
# The numbers count up and are never given twice (SQLite takes one writer at a
# time, so they also become visible in order). A listener that remembers the last
# number it saw misses nothing and sees nothing twice. Rows are kept for a week
# (PurgeEventsJob); a listener that was away for longer is told there is a gap.
#
# Written where the intent is known, by the controllers and the mail sync, not in
# the models' callbacks: a card is moved with update_all, mail is copied and
# removed again while it syncs, and the demo makes its example workspace directly.
class Event < ApplicationRecord
  KINDS = %w[
    mail.received mail.moved mail.archived mail.unarchived mail.deleted
    card.created card.updated card.moved card.commented card.archived card.unarchived card.deleted
    chat.message
  ].freeze
  KEPT_FOR = 7.days
  # A title or a subject is somebody else's text: one line, and not a long one
  TEXT_LIMIT = 200
  EXCERPT = 140
  # What would let text pretend to be something else where it is printed: control
  # characters, and the marks that turn the direction of writing around
  UNPRINTABLE = /[\p{Cc}\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069\uFEFF]/

  belongs_to :tool, optional: true
  belongs_to :user, optional: true

  validates :kind, inclusion: { in: KINDS }

  # Of the tools someone is on now, and from when they came on
  scope :visible_to, ->(user) {
    joins("INNER JOIN collaborators ON collaborators.tool_id = events.tool_id")
      .where(collaborators: { user_id: user.id })
      .where("events.created_at >= collaborators.created_at")
  }
  # "mail" is every kind of mail event, "card.moved" that one kind
  scope :of_kinds, ->(kinds) {
    exact, families = Array(kinds).partition { |kind| kind.include?(".") }
    families.inject(where(kind: exact)) { |scope, family| scope.or(where("events.kind LIKE ?", "#{sanitize_sql_like(family)}.%")) }
  }
  scope :not_made_with, ->(access_token) {
    where(access_token_id: nil).or(where.not(access_token_id: access_token.id))
  }

  after_create_commit :signal

  class << self
    # What happened, to which record, and the few words that say it. Who did it is
    # whoever is asking now, with the token they ask with; a job has nobody.
    # Writing an event down never stops what it is about.
    def record(kind, tool:, record: nil, **data)
      token = Current.access_token
      create!(kind: kind, tool_id: tool.id, record_id: record&.id, user: Current.user,
        access_token_id: token&.id, via: token&.name, agent: token&.agent? || false, data: tidy(data))
    rescue StandardError => error
      raise if Rails.env.local?

      Rails.error.report(error, handled: true, context: { event: kind, tool_id: tool&.id })
      nil
    end

    # The first lines of something written, as an event carries them
    def excerpt(text)
      line(text, limit: EXCERPT)
    end

    def line(text, limit: TEXT_LIMIT)
      text.to_s.gsub(UNPRINTABLE, " ").squish.truncate(limit)
    end

    def kind?(name)
      name.to_s.in?(KINDS) || KINDS.any? { |kind| kind.start_with?("#{name}.") }
    end

    # Whether rows after this number are gone: purged since, or never of this server
    def gap_after?(number)
      oldest, newest = minimum(:id), maximum(:id).to_i
      number > newest || (oldest.present? && number < oldest - 1)
    end

    # The newest row stays whatever its age, so the highest number given is known
    def purge
      where(created_at: ...KEPT_FOR.ago).where.not(id: maximum(:id)).delete_all
    end

    private
      def tidy(data)
        data.compact.transform_values { |value| value.is_a?(String) ? line(value) : value }
      end
  end

  # Whether this token is the one it was made with
  def made_with?(access_token)
    access_token.present? && access_token_id == access_token.id
  end

  private
    # Only that there is something, and its number: every listener asks for the
    # events itself and is given what it may see (EventsChannel)
    def signal
      Collaborator.where(tool_id: tool_id).pluck(:user_id).each do |user_id|
        ActionCable.server.broadcast(EventsChannel.stream_name(user_id), { id: id })
      end
    # A signal that isn't given costs a listener time, not the event: it asks by itself too
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { event_id: id })
    end
end
