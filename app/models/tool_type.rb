# frozen_string_literal: true

class ToolType < ApplicationRecord
  has_many :tools, dependent: :restrict_with_error

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :icon, presence: true

  scope :enabled, -> { where(enabled: true) }

  def to_param
    slug
  end
end
