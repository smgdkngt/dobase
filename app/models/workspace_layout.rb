# frozen_string_literal: true

# The tiling workspace as someone left it: which tiles are open, where, and on which
# desktop (workspace_controller.js). One per person, so every browser they use shows
# the same arrangement. What is in it is the browser's to make sense of; here it is
# kept, counted, and said to the other browsers.
class WorkspaceLayout < ApplicationRecord
  # Nine desktops of tiles are a few kilobytes
  MAX_BYTES = 64.kilobytes
  PARTS = %w[desk desks tiles].freeze

  belongs_to :user

  validate :small_enough

  # Keeps an arrangement made from the one kept here (`from` is its revision). False
  # when another browser changed it since: this one then takes what is kept instead
  # of laying its older arrangement over it.
  def keep(state, from:, by: nil)
    with_lock do
      return false unless revision == from

      update!(state: state.slice(*PARTS), revision: revision + 1)
    end
    ActionCable.server.broadcast("notifications:#{user_id}", { type: "workspace", revision: revision, by: by }.compact)
    true
  end

  private

  def small_enough
    errors.add(:state, "is too large") if state.to_json.bytesize > MAX_BYTES
  end
end
