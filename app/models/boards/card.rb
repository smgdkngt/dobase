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

    # Every way a card is saved or removed is an event, whoever does it and from
    # where: a write that should be heard only has to go through the model
    # The description is rich text, saved beside the card: whether this save changes
    # it is only known before
    before_save { @description_changed = association(:rich_text_description).target&.changed? }
    after_save :record_what_was_saved
    after_destroy { record_event(:deleted) }

    # Places the card at `position` (0-based, clamped) in `target`, counting the
    # column the way it is shown: only its open cards, with the archived ones
    # kept after them. Renumbers the cards around it. Without a position the
    # card goes to the bottom, under the last open card.
    def move_to(target, position: nil, by: nil)
      transaction do
        others = target.cards.where.not(id: id)
        open_cards = others.active.to_a
        siblings = open_cards + others.archived.to_a
        index = position.nil? ? open_cards.size : position.to_i.clamp(0, open_cards.size)

        siblings.each_with_index do |card, sibling_index|
          Card.where(id: card.id).update_all(position: sibling_index < index ? sibling_index : sibling_index + 1)
        end
        update!(column: target, position: index, updated_by: by || updated_by)
      end
    end

    # What happened to the card, for whoever listens from outside the browser (Event)
    def record_event(kind, **data)
      Event.record("card.#{kind}", tool: column.board.tool, record: self, title: title, column: column.name, **data)
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

    # The kind of event is what the save changed. A card that only changes places in
    # its column, or is saved as it was, is none.
    def record_what_was_saved
      if previously_new_record?
        record_event(:created)
      elsif saved_change_to_column_id?
        record_event(:moved, moved_from: Column.find_by(id: column_id_before_last_save)&.name)
      elsif saved_change_to_archived_at?
        record_event(archived? ? :archived : :unarchived)
      elsif (changed = changed_for_event).any?
        record_event(:updated, changed: changed, assignee: (assigned_user&.name if changed.include?("assignee")))
      end
    end

    def changed_for_event
      changed = saved_changes.keys & %w[title color due_date assigned_user_id]
      changed << "description" if @description_changed
      changed.map { |name| name == "assigned_user_id" ? "assignee" : name }
    end

    def assignee_must_be_on_tool
      return if assigned_user_id.nil?

      unless assigned_user && column.board.tool.accessible_by?(assigned_user)
        errors.add(:assigned_user, "must be a collaborator on this tool")
      end
    end
  end
end
