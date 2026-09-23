# frozen_string_literal: true

module Demo
  # Removes demo visitors a day after they came, with their teammates and workspaces
  class CleanupJob < ApplicationJob
    queue_as :default

    def perform
      return unless Demo.enabled?

      # A visitor's teammates are made with them, so they expire with them
      expired = Demo.visitors.where(created_at: ...Demo::LIFETIME.ago)
      expired_teammates = Demo.teammates.where(created_at: ...Demo::LIFETIME.ago)

      # The tools go first, even ones a visitor made someone else co-owner of:
      # removing the visitor would hand those over and keep them around.
      Tool.where(owner_id: expired.select(:id)).or(Tool.where(owner_id: expired_teammates.select(:id))).find_each(&:destroy!)
      # A tool a visitor handed over by deleting their account went to a teammate:
      # their own, or one of the teammates every workspace shared before they had their own
      shared_teammates = User.where(email_address: Workspace::TEAMMATES.pluck(:email_address))
      Tool.where(owner_id: shared_teammates.select(:id), created_at: ...Demo::LIFETIME.ago).find_each(&:destroy!)

      expired.find_each(&:destroy!)
      expired_teammates.find_each(&:destroy!)
    end
  end
end
