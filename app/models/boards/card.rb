# frozen_string_literal: true

module Boards
  class Card < ApplicationRecord
    self.table_name = "cards"

    belongs_to :column, class_name: "Boards::Column"
    belongs_to :assigned_user, class_name: "User", optional: true
    has_many :comments, class_name: "Boards::Comment", dependent: :destroy
    has_many :attachments, class_name: "Boards::Attachment", dependent: :destroy
    has_rich_text :description

    validates :title, presence: true

    scope :active, -> { where(archived_at: nil) }
    scope :archived, -> { where.not(archived_at: nil) }

    def archived? = archived_at.present?

    COLORS = %w[red orange yellow green blue purple].freeze

    validates :color, inclusion: { in: COLORS }, allow_blank: true
  end
end
