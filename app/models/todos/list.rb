# frozen_string_literal: true

module Todos
  class List < ApplicationRecord
    self.table_name = "todo_lists"

    belongs_to :tool
    has_many :items, -> { order(:position) }, class_name: "Todos::Item", foreign_key: :todo_list_id, dependent: :destroy

    validates :title, presence: true

    def self.create_default_for(tool)
      create!(tool: tool, title: "To Do", position: 0)
    end
  end
end
