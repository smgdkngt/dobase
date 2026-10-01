# frozen_string_literal: true

require "net/imap"

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

  # A folder's name as it was given. The server has it in modified UTF-7 (RFC 3501, 5.1.3),
  # where "Büro" is "B&APw-ro" and "&" is "&-". That stays the folder's name for the server
  # and in links; this is the name to show.
  def mail_folder_name(folder)
    Net::IMAP.decode_utf7(folder.to_s).scrub
  rescue StandardError
    folder.to_s
  end

  # The account's own folders as the server nests them: in alphabetical order, each
  # subfolder under its parent and named by its own part ("Clients/Acme" is Acme)
  def mail_folder_tree(folders)
    # The server separates the levels with a / or a ., depending on the server
    parents = folders.index_with do |folder|
      folders.select { |other| other != folder && folder.start_with?("#{other}/", "#{other}.") }.max_by(&:length)
    end

    branch = ->(parent, depth) do
      folders.select { |folder| parents[folder] == parent }.sort_by { |folder| ActiveSupport::Inflector.transliterate(mail_folder_name(folder)).downcase }.flat_map do |folder|
        label = mail_folder_name(parent ? folder.delete_prefix(parent)[1..] : folder)
        [ { key: folder, label: label, name: mail_folder_name(folder), icon: "folder", depth: depth }, *branch.(folder, depth + 1) ]
      end
    end
    branch.(nil, 0)
  end
end
