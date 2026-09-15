# frozen_string_literal: true

module Boards
  class Card < ApplicationRecord
    include Trackable
    self.table_name = "cards"

    belongs_to :column, class_name: "Boards::Column"
    belongs_to :assigned_user, class_name: "User", optional: true
    has_many :comments, class_name: "Boards::Comment", dependent: :destroy
    has_many :attachments, class_name: "Boards::Attachment", dependent: :destroy
    has_rich_text :description

    validates :title, presence: true
    validate :assignee_must_be_on_tool, if: :assigned_user_id_changed?

    scope :active, -> { where(archived_at: nil) }
    scope :archived, -> { where.not(archived_at: nil) }
    scope :assigned_to, ->(user) { where(assigned_user: user) }
    scope :unassigned, -> { where(assigned_user_id: nil) }

    def archived? = archived_at.present?

    COLORS = %w[red orange yellow green blue purple].freeze

    validates :color, inclusion: { in: COLORS }, allow_blank: true

    # Places the card at `position` (0-based, clamped) in `target`, renumbering
    # the cards around it. Without a position the card goes to the bottom.
    def move_to(target, position: nil, by: nil)
      transaction do
        siblings = target.cards.where.not(id: id).to_a
        index = position.nil? ? siblings.size : position.to_i.clamp(0, siblings.size)

        siblings.each_with_index do |card, sibling_index|
          Card.where(id: card.id).update_all(position: sibling_index < index ? sibling_index : sibling_index + 1)
        end
        update!(column: target, position: index, updated_by: by || updated_by)
      end
    end

    # Lets the assignee know, unless they assigned themselves, muted the tool or
    # aren't on it at all.
    def notify_assignee(assigner)
      return if assigned_user.nil? || assigned_user == assigner

      tool = column.board.tool
      return if tool.muted_by?(assigned_user) || !tool.accessible_by?(assigned_user)

      CardAssignmentNotifier.with(card: self, assigner: assigner, tool: tool).deliver(assigned_user)
      assigned_user.prune_notifications!
    end

    private

    def assignee_must_be_on_tool
      return if assigned_user_id.nil?

      unless assigned_user && column.board.tool.accessible_by?(assigned_user)
        errors.add(:assigned_user, "must be a collaborator on this tool")
      end
    end
  end
end
