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

  # The account's own folders as the server nests them: in alphabetical order, each
  # subfolder under its parent and named by its own part ("Clients/Acme" is Acme)
  def mail_folder_tree(folders)
    # The server separates the levels with a / or a ., depending on the server
    parents = folders.index_with do |folder|
      folders.select { |other| other != folder && folder.start_with?("#{other}/", "#{other}.") }.max_by(&:length)
    end

    branch = ->(parent, depth) do
      folders.select { |folder| parents[folder] == parent }.sort_by(&:downcase).flat_map do |folder|
        label = parent ? folder.delete_prefix(parent)[1..] : folder
        [ { key: folder, label: label, icon: "folder", depth: depth }, *branch.(folder, depth + 1) ]
      end
    end
    branch.(nil, 0)
  end
end
