# frozen_string_literal: true

module Boards
  class Board < ApplicationRecord
    self.table_name = "boards"

    belongs_to :tool
    has_many :columns, -> { order(:position) }, class_name: "Boards::Column", dependent: :destroy
    has_many :cards, through: :columns

    def self.create_default_for(tool)
      board = create!(tool: tool)
      board.columns.create!([
        { name: Translation.translate("To Do"), position: 0 },
        { name: Translation.translate("In Progress"), position: 1 },
        { name: Translation.translate("Done"), position: 2 }
      ])
      board
    end
  end
end
