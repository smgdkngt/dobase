# frozen_string_literal: true

module Files
  class Folder < ApplicationRecord
    self.table_name = "file_folders"

    MAX_DEPTH = 10

    belongs_to :tool
    belongs_to :parent, class_name: "Files::Folder", optional: true
    has_many :children, class_name: "Files::Folder", foreign_key: :parent_id, dependent: :destroy
    has_many :files, class_name: "Files::Item", foreign_key: :folder_id, dependent: :destroy
    has_one :share, as: :shareable, class_name: "Files::Share", dependent: :destroy

    validates :name, presence: true
    validate :depth_limit

    before_save :set_depth

    scope :roots, -> { where(parent_id: nil) }
    scope :ordered, -> { order(:position, :name) }

    def ancestors
      return [] unless parent
      [ parent ] + parent.ancestors
    end

    def breadcrumbs
      ancestors.reverse + [ self ]
    end

    def all_files
      files + children.flat_map(&:all_files)
    end

    def image_files
      all_files.select(&:image?)
    end

    private

    def set_depth
      self.depth = parent ? parent.depth + 1 : 0
    end

    def depth_limit
      if parent && parent.depth >= MAX_DEPTH - 1
        errors.add(:base, "Maximum folder depth of #{MAX_DEPTH} reached")
      end
    end
  end
end
