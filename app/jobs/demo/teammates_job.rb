# frozen_string_literal: true

module Demo
  # For a couple of minutes after a visitor arrives, their teammates come alive: they
  # turn up in tools, type, say hello, comment and hand over a todo, so the workspace
  # feels like one people work in. They go through the models like anyone else, so
  # the visitor sees it the way they would see a colleague: chat messages and
  # notifications arrive live, and faces show up in the sidebar and topbars.
  #
  # One beat per run; each run queues the next. A beat whose teammate, tool, card
  # or visitor is gone is skipped, and a teammate someone has joined as (their link
  # in the demo banner) is left to that person.
  class TeammatesJob < ApplicationJob
    queue_as :default
    # The visitor has been removed
    discard_on ActiveJob::DeserializationError

    # Seconds after the visitor arrived; who does what, where. %{visitor} mentions them.
    SCRIPT = [
      { at: 12, who: "marcus", does: :type, tool: "Team Chat" },
      { at: 16, who: "marcus", does: :say, tool: "Team Chat",
        text: "Hi %{visitor}, welcome to Moonshot Snacks 👋 Make yourself at home: move a card, tick off a todo or just say hi here." },
      { at: 40, who: "priya", does: :look, tool: "Product Launch", card: "Design landing page" },
      { at: 55, who: "priya", does: :comment, tool: "Product Launch", card: "Design landing page",
        text: "%{visitor}, the hero with the floating snacks is on staging now. Too much, or just right?" },
      { at: 75, who: "jake", does: :look, tool: "Launch Tasks" },
      { at: 85, who: "jake", does: :hand_over, tool: "Launch Tasks", list: "Pre-Launch Checklist",
        todo: "Taste-test the new Orbit Rings batch" },
      { at: 112, who: "marcus", does: :type, tool: "Team Chat" },
      { at: 116, who: "marcus", does: :say, tool: "Team Chat",
        text: "%{visitor}, want to see us work together live? Press Try it together at the bottom of the page and open one of our links in a private window." }
    ].freeze

    def self.start(visitor)
      set(wait: SCRIPT.first[:at].seconds).perform_later(visitor)
    end

    def perform(visitor, beat = 0)
      return unless Demo.enabled?
      return unless (step = SCRIPT[beat])

      play(visitor, step)

      if (following = SCRIPT[beat + 1])
        self.class.set(wait: (following[:at] - step[:at]).seconds).perform_later(visitor, beat + 1)
      end
    end

    private

    attr_reader :visitor

    def play(visitor, step)
      @visitor = visitor
      teammate = Demo.teammates_of(visitor).find_by("email_address LIKE ?", "#{step[:who]}-%")
      tool = visitor.owned_tools.find_by(name: step[:tool])
      return unless teammate && tool&.accessible_by?(teammate)
      # Someone joined as this teammate, and does the talking now
      return if teammate.sessions.exists?

      send(step[:does], teammate, tool, step)
    rescue ActiveRecord::ActiveRecordError
      # Whatever the visitor changed meanwhile ends this beat, not the rest of the script
    end

    def type(teammate, tool, _step)
      return unless (chat = tool.chat)

      PresenceChannel.announce(tool, teammate)
      ChatChannel.typing(chat, teammate)
    end

    def say(teammate, tool, step)
      return unless (chat = tool.chat)

      PresenceChannel.announce(tool, teammate)
      ChatChannel.stop_typing(chat, teammate)
      chat.messages.create!(user: teammate, body: words(step[:text]))
    end

    def look(teammate, tool, step)
      card = card_in(tool, step[:card]) if step[:card]
      PresenceChannel.announce(tool, teammate, context: card && "card:#{card.id}")
    end

    def comment(teammate, tool, step)
      return unless (card = card_in(tool, step[:card]))

      PresenceChannel.announce(tool, teammate, context: "card:#{card.id}")
      card.comments.create!(user: teammate, body: words(step[:text]))
    end

    # A new todo for the visitor, at the top of the list, which tells them so
    def hand_over(teammate, tool, step)
      return unless (list = tool.todo_lists.find_by(title: step[:list]))

      item = list.items.create!(title: step[:todo], assigned_user: visitor, due_date: 2.days.from_now.to_date,
        position: list.items.maximum(:position).to_i + 1, created_by: teammate, updated_by: teammate)
      item.move_to(list, position: 0, by: teammate)
      PresenceChannel.announce(tool, teammate, context: "todo:#{item.id}")
      item.notify_assignee(teammate)
    end

    def card_in(tool, title)
      tool.board&.cards&.find_by(title: title)
    end

    # Mentions the way the editor stores them, so the visitor is notified
    def words(text)
      mention = %(<span data-id="#{visitor.id}" class="mention">@#{ERB::Util.html_escape(visitor.name)}</span>)
      "<p>#{format(ERB::Util.html_escape(text), visitor: mention)}</p>"
    end
  end
end
