# frozen_string_literal: true

module Sidebar
  class Membership < ApplicationRecord
    self.table_name = "sidebar_memberships"

    belongs_to :group, class_name: "Sidebar::Group", foreign_key: "sidebar_group_id"
    belongs_to :tool

    validates :tool_id, uniqueness: { scope: :sidebar_group_id }
  end
end
