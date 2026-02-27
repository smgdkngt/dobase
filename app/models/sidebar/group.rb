# frozen_string_literal: true

module Sidebar
  class Group < ApplicationRecord
    self.table_name = "sidebar_groups"

    belongs_to :user
    has_many :memberships, -> { order(:position) }, class_name: "Sidebar::Membership", foreign_key: "sidebar_group_id", dependent: :destroy
    has_many :tools, through: :memberships

    validates :name, presence: true

    scope :ordered, -> { order(:position) }
  end
end
