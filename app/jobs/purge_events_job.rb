# frozen_string_literal: true

# Events are kept for a week: long enough for a listener that was away
class PurgeEventsJob < ApplicationJob
  queue_as :default

  def perform
    Event.purge
  end
end
