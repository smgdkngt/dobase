# frozen_string_literal: true

class ImapSyncJob < ApplicationJob
  queue_as :default

  def perform(mail_account_id, action, uid, folder, *args)
    mail_account = Mails::Account.find_by(id: mail_account_id)
    return unless mail_account

    service = ImapSyncService.new(mail_account)

    case action
    when "mark_as_read"
      service.mark_as_read(uid, folder: folder)
    when "mark_as_unread"
      service.mark_as_unread(uid, folder: folder)
    when "set_starred"
      starred = args.first
      service.set_starred(uid, starred, folder: folder)
    when "move_to_folder"
      destination = args.first
      service.move_to_folder(uid, source_folder: folder, destination_folder: destination)
    when "delete_message"
      service.delete_message(uid, folder: folder)
    end
  end
end
