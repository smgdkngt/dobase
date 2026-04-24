# frozen_string_literal: true

module Calendars
  class Calendar < ApplicationRecord
    self.table_name = "calendar_calendars"

    belongs_to :tool
    belongs_to :account, class_name: "Calendars::Account", foreign_key: "calendar_account_id", optional: true
    has_many :events, class_name: "Calendars::Event", foreign_key: "calendar_id", dependent: :destroy

    validates :remote_id, presence: true, uniqueness: { scope: :calendar_account_id }, if: :account
    validates :name, presence: true

    before_validation :infer_tool_from_account, if: -> { tool.nil? && account }

    scope :enabled, -> { where(enabled: true) }
    scope :writable, -> { where(read_only: false) }
    scope :by_position, -> { order(position: :asc) }

    before_save :ensure_single_default, if: -> { is_default_changed? && is_default? }
    after_commit :sync_to_caldav, if: :should_sync_to_caldav?

    DEFAULT_COLOR = "#3b82f6"

    def color_hex
      color.presence || DEFAULT_COLOR
    end

    private

    def infer_tool_from_account
      self.tool = account.tool
    end

    def ensure_single_default
      tool.calendars.where.not(id: id).update_all(is_default: false)
    end

    def should_sync_to_caldav?
      account.present? && remote_url.present? && (saved_change_to_name? || saved_change_to_color?)
    end

    def sync_to_caldav
      SyncCalendarPropertiesJob.perform_later(id)
    end
  end
end
