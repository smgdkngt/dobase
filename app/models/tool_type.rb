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

  # The name and description in the page's language: the rows are English (db/seeds.rb),
  # and their Persian is in config/locales/fa/ui.yml like any other text
  def human_name = _(name)

  def human_description = _(description.to_s)
end
