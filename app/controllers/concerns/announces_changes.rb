# frozen_string_literal: true

# Whatever changes something in a tool says so to every page that has the tool open,
# and each of those draws itself again (Tool#announce_change, live_controller.js).
# Here and nowhere else: the pages of the app, the API and the CLI all come through a
# controller, so a card made from a terminal shows on a board that is open somewhere.
#
# Every request that isn't a GET and went well counts, for whichever tool it was let
# into. What it changed is not said: a page that hears it asks for itself again, and
# is given what its reader may see.
#
# An action whose change is nobody else's to see says so with `announces_no_change`
# (a tool marked as seen, a chat read), or while it runs with `announce_no_change`
# (a column folded away for yourself). test/integration/changes_announced_test.rb
# lists those, each with its reason. What changes a tool without a request (a mail
# or calendar sync) calls Tool#announce_change itself.
module AnnouncesChanges
  extend ActiveSupport::Concern

  included do
    class_attribute :actions_announcing_no_change, default: [].freeze
    after_action :announce_change
  end

  class_methods do
    def announces_no_change(*actions)
      self.actions_announcing_no_change += actions.map(&:to_s)
    end

    def announces_change?(action)
      actions_announcing_no_change.exclude?(action.to_s)
    end
  end

  private
    def announce_no_change
      @announce_no_change = true
    end

    def announce_change
      return if request.get? || request.head? || @announce_no_change
      return unless self.class.announces_change?(action_name)
      return unless @tool&.persisted? && response.status < 400

      # The page that asked has drawn the change itself, and knows its own requests
      @tool.announce_change(by: request.headers["X-Turbo-Request-Id"].presence)
    end
end
