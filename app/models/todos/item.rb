# frozen_string_literal: true

module Todos
  class Item < ApplicationRecord
    include Trackable
    self.table_name = "todo_items"

    belongs_to :list, class_name: "Todos::List", foreign_key: :todo_list_id
    belongs_to :assigned_user, class_name: "User", optional: true
    has_many :comments, class_name: "Todos::Comment", foreign_key: :todo_item_id, dependent: :destroy
    has_many :attachments, class_name: "Todos::Attachment", foreign_key: :todo_item_id, dependent: :destroy
    has_rich_text :description

    RECURRENCE_RULES = %w[daily weekly monthly].freeze

    validates :title, presence: true
    validates :recurrence_rule, inclusion: { in: RECURRENCE_RULES }, allow_nil: true

    scope :pending, -> { where(completed_at: nil) }
    scope :recently_completed, -> { where(completed_at: 24.hours.ago..) }
    scope :completed_hidden, -> { where(completed_at: ...24.hours.ago) }
    scope :visible, -> { pending.or(recently_completed) }
    scope :assigned_to, ->(user) { where(assigned_user: user) }
    scope :unassigned, -> { where(assigned_user_id: nil) }
    scope :recurring, -> { where.not(recurrence_rule: nil) }

    def completed? = completed_at.present?
    def recurring? = recurrence_rule.present?

    # Creates the next instance of a recurring item with the schedule advanced
    # one interval. Comments and attachments stay on the completed record as
    # history; the new instance starts fresh.
    def spawn_next_instance!
      return unless recurring?

      new_item = list.items.new(
        title: title,
        position: 0,
        assigned_user_id: assigned_user_id,
        recurrence_rule: recurrence_rule,
        due_date: next_due_date,
        created_by: created_by,
        updated_by: updated_by
      )
      new_item.description = description.body if description.present?
      new_item.save!
      new_item
    end

    def recurrence_description
      case recurrence_rule
      when "daily"   then "Daily"
      when "weekly"  then "Weekly"
      when "monthly" then "Monthly"
      end
    end

    private
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
