# frozen_string_literal: true

module Todos
  class Item < ApplicationRecord
    include Trackable
    self.table_name = "todo_items"

    belongs_to :list, class_name: "Todos::List", foreign_key: :todo_list_id
    belongs_to :assigned_user, class_name: "User", optional: true
    has_many :comments, class_name: "Todos::Comment", foreign_key: :todo_item_id, dependent: :destroy
    has_many :attachments, class_name: "Todos::Attachment", foreign_key: :todo_item_id, dependent: :destroy
    belongs_to :spawned_from, class_name: "Todos::Item", optional: true
    has_one :spawned_copy, class_name: "Todos::Item", foreign_key: :spawned_from_id, inverse_of: :spawned_from, dependent: :nullify
    has_rich_text :description

    RECURRENCE_RULES = %w[daily weekly monthly].freeze

    validates :title, presence: true
    validates :recurrence_rule, inclusion: { in: RECURRENCE_RULES }, allow_nil: true
    validate :assignee_must_be_on_tool, if: :assigned_user_id_changed?

    scope :pending, -> { where(completed_at: nil) }
    scope :completed, -> { where.not(completed_at: nil) }
    scope :recently_completed, -> { where(completed_at: 24.hours.ago..) }
    scope :completed_hidden, -> { where(completed_at: ...24.hours.ago) }
    scope :visible, -> { pending.or(recently_completed) }
    scope :assigned_to, ->(user) { where(assigned_user: user) }
    scope :unassigned, -> { where(assigned_user_id: nil) }
    scope :recurring, -> { where.not(recurrence_rule: nil) }

    def completed? = completed_at.present?

    # Matches the recently_completed scope
    def recently_completed? = completed? && completed_at >= 24.hours.ago

    def recurring? = recurrence_rule.present?

    # Creates the next instance of a recurring item with the schedule advanced
    # one interval, at the top of the list. Comments and attachments stay on the
    # completed record as history; the new instance starts fresh, unassigned if
    # the assignee has since left the tool.
    def spawn_next_instance!
      return unless recurring?

      new_item = list.items.new(
        title: title,
        assigned_user_id: (assigned_user_id if assignee_on_tool?),
        recurrence_rule: recurrence_rule,
        due_date: next_due_date,
        created_by: created_by,
        updated_by: updated_by,
        spawned_from: self
      )
      new_item.description = description.body if description.present?
      new_item.save!
      new_item.move_to(list, position: 0, by: updated_by)
      new_item
    end

    # Un-completing a repeating item takes back the copy that completing it
    # made, as long as nobody has picked that copy up: it's still open, and
    # nothing has been said or attached on it.
    def discard_untouched_copy!
      copy = spawned_copy
      return if copy.nil? || copy.completed? || copy.comments.any? || copy.attachments.any?

      copy.destroy!
    end

    def recurrence_description
      case recurrence_rule
      when "daily"   then "Daily"
      when "weekly"  then "Weekly"
      when "monthly" then "Monthly"
      end
    end

    # Places the item at `position` (0-based, clamped) in `target`, counting the
    # list the way it is shown: open items first, then completed ones. Renumbers
    # the items around it. Without a position the item goes to the bottom.
    def move_to(target, position: nil, by: nil)
      transaction do
        others = target.items.where.not(id: id)
        siblings = others.pending.to_a + others.completed.to_a
        index = position.nil? ? siblings.size : position.to_i.clamp(0, siblings.size)

        siblings.each_with_index do |item, sibling_index|
          Item.where(id: item.id).update_all(position: sibling_index < index ? sibling_index : sibling_index + 1)
        end
        update!(list: target, position: index, updated_by: by || updated_by)
      end
    end

    # Lets the assignee know, unless they assigned themselves, muted the tool or
    # aren't on it at all.
    def notify_assignee(assigner)
      return if !assignee_on_tool? || assigned_user == assigner || list.tool.muted_by?(assigned_user)

      TodoAssignmentNotifier.with(item: self, assigner: assigner, tool: list.tool).deliver(assigned_user)
      assigned_user.prune_notifications!
    end

    private
      def assignee_on_tool?
        assigned_user.present? && list.tool.accessible_by?(assigned_user)
      end

      def assignee_must_be_on_tool
        return if assigned_user_id.nil? || assignee_on_tool?

        errors.add(:assigned_user, "must be a collaborator on this tool")
      end

      def next_due_date
        return nil if due_date.blank?

        case recurrence_rule
        when "daily"   then due_date + 1.day
        when "weekly"  then due_date + 1.week
        when "monthly" then due_date + 1.month
        end
      end
  end
end
