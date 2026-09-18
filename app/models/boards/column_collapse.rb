# frozen_string_literal: true

module Boards
  # One person having folded one board column out of their own way.
  class ColumnCollapse < ApplicationRecord
    self.table_name = "column_collapses"

    belongs_to :column, class_name: "Boards::Column"
    belongs_to :user
  end
end
