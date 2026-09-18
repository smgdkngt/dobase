# frozen_string_literal: true

module Boards
  class Column < ApplicationRecord
    include Trackable
    self.table_name = "columns"

    belongs_to :board, class_name: "Boards::Board"
    has_many :cards, -> { order(:position) }, class_name: "Boards::Card", dependent: :destroy
    has_many :collapses, class_name: "Boards::ColumnCollapse", dependent: :destroy

    validates :name, presence: true

    def collapsed_for?(user)
      collapses.exists?(user_id: user.id)
    end

    def collapse_for(user)
      collapses.create_or_find_by!(user: user)
    end

    def expand_for(user)
      collapses.where(user: user).delete_all
    end

    # The columns of these boards that this person has folded away, so a board
    # renders without asking once per column.
    def self.collapsed_ids_for(user, columns)
      ColumnCollapse.where(user_id: user.id, column_id: columns).pluck(:column_id).to_set
    end
  end
end
