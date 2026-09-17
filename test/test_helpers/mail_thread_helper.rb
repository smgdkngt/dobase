# frozen_string_literal: true

module MailThreadHelper
  # Two inbox messages in one conversation, with UIDs 201 and 202, oldest first
  def create_mail_thread(account = mails_accounts(:primary))
    [ 201, 202 ].map.with_index do |uid, index|
      account.messages.create!(message_id: "<lunch-#{uid}@example.com>", folder: "INBOX", uid: uid, subject: "Lunch?",
        from_address: "ann@example.com", to_addresses: "[]", sent_at: (2 - index).hours.ago, thread_id: "thread-lunch")
    end
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include MailThreadHelper
end
