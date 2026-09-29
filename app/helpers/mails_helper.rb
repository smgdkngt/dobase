# frozen_string_literal: true

module MailsHelper
  # The built-in folders to switch between, with the counts that show as a badge
  def mail_folders(inbox_unread:, drafts_count:, trash_count:)
    [
      { key: "inbox",   label: "Inbox",   icon: "inbox",    badge: inbox_unread },
      { key: "drafts",  label: "Drafts",  icon: "file-pen", badge: drafts_count },
      { key: "starred", label: "Starred", icon: "star" },
      { key: "sent",    label: "Sent",    icon: "send" },
      { key: "archive", label: "Archive", icon: "archive" },
      { key: "trash",   label: "Trash",   icon: "trash-2",  badge: trash_count }
    ]
  end
end
