# frozen_string_literal: true

module Files
  class Folder < ApplicationRecord
    include Trackable
    self.table_name = "file_folders"

    MAX_DEPTH = 10

    belongs_to :tool
    belongs_to :parent, class_name: "Files::Folder", optional: true
    has_many :children, class_name: "Files::Folder", foreign_key: :parent_id, dependent: :destroy
    has_many :files, class_name: "Files::Item", foreign_key: :folder_id, dependent: :destroy
    has_one :share, as: :shareable, class_name: "Files::Share", dependent: :destroy

    validates :name, presence: true
    validate :depth_limit
    validate :parent_outside_own_subtree, on: :update, if: :parent_id_changed?

    before_save :set_depth
    after_update :restamp_subtree_depth, if: :saved_change_to_depth?

    scope :roots, -> { where(parent_id: nil) }
    scope :ordered, -> { order(:position, :name) }

    def ancestors
      return [] unless parent
      [ parent ] + parent.ancestors
    end

    def breadcrumbs
      ancestors.reverse + [ self ]
    end

    # The images the share page shows, which are the ones its gallery can open:
    # a subfolder's files have no page of their own behind a share link.
    def image_files
      files.select(&:image?)
    end

    private

    def set_depth
      self.depth = parent ? parent.depth + 1 : 0
    end

    # A folder lands under its new parent with everything below it, so the whole
    # subtree has to fit within the depth limit, not just the folder itself.
    def depth_limit
      return unless parent && (new_record? || parent_id_changed?)

      if parent.depth + 1 + subtree_height > MAX_DEPTH - 1
        errors.add(:base, "Maximum folder depth of #{MAX_DEPTH} reached")
      end
    end

    # How many levels of folders sit below this one.
    def subtree_height
      height = 0
      ids = children.pluck(:id)

      while ids.any?
        height += 1
        ids = Folder.where(parent_id: ids).pluck(:id)
      end

      height
    end

    # depth is stored, so moving a folder has to restamp everything under it.
    def restamp_subtree_depth
      level = children.pluck(:id)
      level_depth = depth

      while level.any?
        level_depth += 1
        Folder.where(id: level).update_all(depth: level_depth)
        level = Folder.where(parent_id: level).pluck(:id)
      end
    end

    # Moving a folder into itself or one of its subfolders would cut it off from the tree.
    def parent_outside_own_subtree
      if parent && parent.breadcrumbs.include?(self)
        errors.add(:base, "A folder can't be moved into itself or one of its subfolders")
      end
    end
  end
end
