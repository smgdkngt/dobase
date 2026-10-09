# frozen_string_literal: true

require "net/imap"

module MailsHelper
  # Emails are designed for a light page, so they keep one in dark mode too (like other
  # mail clients); the host page frames them on a light surface instead of recoloring them.
  MAIL_FRAME_STYLES = <<~CSS
    :root { color-scheme: light; }
    body {
      margin: 0;
      padding: 0;
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      font-size: 14px;
      line-height: 1.5;
      color: #1d1d1f;
      background: #fff;
      word-wrap: break-word;
      overflow-wrap: break-word;
    }
    a { color: #0071e3; }
    img { max-width: 100%; height: auto; }
    table { max-width: 100%; }
    pre { white-space: pre-wrap; overflow-x: auto; }
    blockquote {
      margin: 0.5em 0;
      padding-left: 1em;
      border-left: 3px solid #d2d2d7;
      color: #6e6e73;
    }
  CSS

  # Until the reader asks for images, nothing loads from outside the email. CSS url()s in
  # <style> survive sanitizing and would otherwise still work as tracking pixels.
  MAIL_FRAME_POLICY = %(<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: cid:; style-src 'unsafe-inline'; font-src data:">)

  # The page a mail is in its frame (srcdoc), which runs no scripts
  def mail_frame_document(body, remote_content: false, styles: nil)
    "<!DOCTYPE html><html><head><meta charset=\"utf-8\">#{MAIL_FRAME_POLICY unless remote_content}<base target=\"_blank\"><style>#{MAIL_FRAME_STYLES}#{styles}</style></head><body>#{body}</body></html>"
  end

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

  # The frame a conversation is read in, beside its list. One per mailbox: two can
  # be on a page (tiles in the workspace's own page), and a link finds its frame by id.
  def mail_frame_id(tool = @tool)
    "mail-content-#{tool.id}"
  end

  # A folder's name as it was given. The server has it in modified UTF-7 (RFC 3501, 5.1.3),
  # where "Büro" is "B&APw-ro" and "&" is "&-", and some servers have it inside the inbox,
  # as "INBOX.Büro". That stays the folder's name for the server and in links; this is the
  # name to show.
  def mail_folder_name(folder, account: @tool&.mail_account)
    name = account ? account.folder_without_prefix(folder) : folder.to_s
    Net::IMAP.decode_utf7(name).scrub
  rescue StandardError
    name || folder.to_s
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

  # Who a message went to, by the header they are in, each with the name they are known by
  # (names: Mails::Account#names_in, once for a conversation). A header nobody is in is left out.
  def mail_recipients(message, names)
    { "To" => message.to_addresses_list, "Cc" => message.cc_addresses_list, "Bcc" => message.bcc_addresses_list }.filter_map do |header, addresses|
      people = addresses.map do |address|
        recipient = Mails::Recipient.from(address.to_s)
        recipient.with(name: recipient.name || names[recipient.address.downcase])
      end
      [ header, people ] if people.any?
    end.to_h
  end

  # The same in one line, by name: what a closed message says
  def mail_recipients_line(recipients)
    recipients.map { |header, people| "#{header}: #{people.map { |person| person.name.presence || person.address }.join(', ')}" }.join(" · ")
  end

  # What a screen reader hears after a recipient's name
  def recipient_more(recipient)
    return ", not a valid address" unless recipient.valid?

    recipient.name.present? ? ", #{recipient.address}" : ""
  end

  # Two letters for someone who is only a name and an address
  def recipient_initials(suggestion)
    words = suggestion.name.to_s.scan(/[[:alnum:]]+/)
    words = [ suggestion.address ] if words.empty?
    (words.size > 1 ? words.first[0] + words.last[0] : words.first[0]).upcase
  end
end
