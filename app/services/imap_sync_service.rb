# frozen_string_literal: true

require "net/imap"

class ImapSyncService
  class ConnectionError < StandardError; end
  class AuthenticationError < StandardError; end
  # The mail server wasn't reached, or the connection broke, while making a change there.
  # Making the change again is safe.
  class Unreachable < ConnectionError; end

  # Failures to find, connect to or keep talking to the mail server, which may pass
  UNREACHABLE = [ SocketError, Timeout::Error, IOError, OpenSSL::SSL::SSLError, Errno::ECONNREFUSED, Errno::ECONNRESET,
                  Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::ETIMEDOUT, Errno::EPIPE, Net::IMAP::ByeResponseError ].freeze

  SPECIAL_FOLDERS = {
    "Sent" => [ :Sent, [ "Sent", "INBOX.Sent", "[Gmail]/Sent Mail", "Sent Messages", "Sent Items" ] ],
    "Drafts" => [ :Drafts, [ "Drafts", "INBOX.Drafts", "[Gmail]/Drafts", "Draft" ] ],
    "Trash" => [ :Trash, [ "Trash", "Deleted Messages", "Deleted Items", "INBOX.Trash", "[Gmail]/Trash", "Bin" ] ]
  }.freeze
  ARCHIVE_FOLDER = [ :Archive, [ "Archive", "Archives", "INBOX.Archive" ] ].freeze

  # New mail fetched per folder per sync, newest first: a big folder fills in over several syncs
  BACKFILL_BATCH = 500
  # A folder bigger than this, like the archive of an old account, only gets its last three months
  FULL_SYNC_MAX = 10_000
  # Messages per FETCH, so a batch of full messages isn't held in memory at once
  FETCH_SLICE = 50

  def initialize(email_account)
    @account = email_account
  end

  def sync_folders
    connect do |imap|
      mailboxes = imap.list("", "*") || []
      # The server's sent, drafts and trash folders are known here as "Sent", "Drafts" and "Trash"
      special = SPECIAL_FOLDERS.keys.index_by { |folder| find_special_folder(mailboxes, folder) }.except(nil)
      # Leave out Gmail's other system folders
      folders = mailboxes.map(&:name).reject { |f| f.start_with?("[Gmail]/") && !special.key?(f) }
      normalized = folders.map { |f| special.fetch(f, f) }.uniq
      special.each { |server_name, folder| adopt_special_folder(server_name, folder) }
      @account.update!(synced_folders: normalized.to_json)
      adopt_archive_folder(mailboxes)
      normalized
    end
  end

  def sync_inbox(limit: 50)
    @account.mark_syncing!

    connect do |imap|
      imap.select("INBOX")
      fetch_recent_emails(imap, "INBOX", limit)
    end

    @account.mark_synced!
    true
  rescue StandardError => e
    @account.mark_sync_error!(e.message)
    raise
  end

  def sync_sent(limit: 50)
    connect do |imap|
      sent_folder = find_sent_folder(imap)
      return unless sent_folder

      imap.select(sent_folder)
      fetch_recent_emails(imap, "Sent", limit)
      file_sent_mail(imap, sent_folder)
    end
  end

  def sync_folder(folder_name, limit: 50)
    connect do |imap|
      imap.select(folder_name)
      fetch_recent_emails(imap, folder_name, limit)
    end
  # A folder the server can't open, or whose messages net-imap can't parse, shouldn't stop the other folders from syncing
  rescue Net::IMAP::NoResponseError, Net::IMAP::ResponseParseError => e
    Rails.logger.warn("Could not sync folder #{folder_name}: #{e.class}: #{e.message}")
  end

  # --- Changes made in Dobase, made on the server afterwards (ImapSyncJob, SyncDraftJob) ---
  # Each raises Unreachable when the server couldn't be reached, for the job to try again.
  # Setting a flag or deleting a message twice comes to the same as once, so those are tried
  # again wherever the connection broke. A move copies and a draft is added: once that has
  # gone to the server it may have arrived, and it isn't tried again (`unrepeatable!`).

  def mark_as_read(uid, folder: "INBOX")
    changing_server("mark email as read on IMAP") do |imap|
      select_folder(imap, folder)
      imap.uid_store(uid, "+FLAGS", [ :Seen ])
    end
  end

  def mark_as_unread(uid, folder: "INBOX")
    changing_server("mark email as unread on IMAP") do |imap|
      select_folder(imap, folder)
      imap.uid_store(uid, "-FLAGS", [ :Seen ])
    end
  end

  def set_starred(uid, starred, folder: "INBOX")
    changing_server("update starred flag on IMAP") do |imap|
      select_folder(imap, folder)
      if starred
        imap.uid_store(uid, "+FLAGS", [ :Flagged ])
      else
        imap.uid_store(uid, "-FLAGS", [ :Flagged ])
      end
    end
  end

  def create_folder(folder_name)
    connect { |imap| imap.create(folder_name) }
    sync_folders
  end

  def save_draft(message)
    changing_server("save draft to IMAP") do |imap|
      raw = build_raw_email(message)
      drafts_folder = find_special_folder(imap.list("", "*"), "Drafts")

      # Delete old draft from server if it exists. A draft restored from the trash has no
      # UID in the drafts folder yet, and is found by its Message-ID.
      if drafts_folder
        imap.select(drafts_folder)
        earlier = message.uid.presence || find_by_message_id(imap, message.message_id)
        remove_from_folder(imap, earlier) if earlier.present?
      end

      # Upload new version
      if drafts_folder
        unrepeatable!
        imap.append(drafts_folder, raw, [ :Draft, :Seen ])
        # Get the UID of the just-appended message
        imap.select(drafts_folder)
        uids = imap.uid_search([ "HEADER", "Message-ID", message.message_id ])
        message.update_column(:uid, uids.last) if uids.any?
      end
    end
  end

  def delete_draft(uid)
    return if uid.blank?

    delete_message(uid, folder: "Drafts")
  end

  # Takes one UID or several in the same folder
  def delete_message(uids, folder:)
    changing_server("delete email #{Array(uids).join(", ")} from #{folder}") do |imap|
      select_folder(imap, folder)
      remove_from_folder(imap, uids)
    end
  end

  def move_to_folder(uid, source_folder:, destination_folder:)
    changing_server("move email #{Array(uid).join(", ")} from #{source_folder} to #{destination_folder}") do |imap|
      source, destination = server_folder_names(imap, source_folder, destination_folder)
      imap.select(source)
      unrepeatable!
      imap.uid_copy(uid, destination)
      remove_from_folder(imap, uid)
    end
  end

  def delete_message_by_message_id(message_id, folder:)
    changing_server("delete email #{message_id} from #{folder}") do |imap|
      select_folder(imap, folder)
      uids = find_by_message_id(imap, message_id)
      remove_from_folder(imap, uids) if uids.any?
    end
  end

  # A moved message gets a new UID in its new folder, so mail that was moved before, like
  # archived mail, is found by its Message-ID.
  def move_to_folder_by_message_id(message_id, source_folder:, destination_folder:)
    changing_server("move email #{message_id} from #{source_folder} to #{destination_folder}") do |imap|
      source, destination = server_folder_names(imap, source_folder, destination_folder)
      imap.select(source)
      uids = find_by_message_id(imap, message_id)
      next if uids.empty?

      unrepeatable!
      imap.uid_copy(uids, destination)
      remove_from_folder(imap, uids)
    end
  end

  # Mail saved before attachments kept their Content-IDs shows the pictures in its text
  # once it has them, so it's fetched again for them
  def fill_in_content_ids
    messages = @account.messages.where("body_html LIKE ?", "%cid:%").where.not(uid: nil)
      .where(id: Mails::Attachment.where(content_id: nil).select(:mail_message_id))
      .select(:id, :mail_account_id, :uid, :folder)
    return if messages.none?

    connect do |imap|
      messages.group_by(&:folder).each do |folder, in_folder|
        select_folder(imap, folder)
        in_folder.each_slice(FETCH_SLICE) do |slice|
          by_uid = slice.index_by(&:uid)
          Array(imap.uid_fetch(slice.map(&:uid), [ "UID", "BODY.PEEK[]" ])).each do |msg|
            message = by_uid[msg.attr["UID"]]
            incoming_message.fill_in_content_ids(message, msg.attr["BODY[]"]) if message && msg.attr["BODY[]"]
          end
        end
      rescue Net::IMAP::NoResponseError => e
        Rails.logger.warn("Couldn't fetch the Content-IDs in #{folder}: #{e.message}")
      end
    end
  end

  private

  def incoming_message
    @incoming_message ||= ::Mails::IncomingMessage.new(@account)
  end

  # Connects for a change the server should get. A server that can't be reached raises
  # Unreachable as long as trying again can't make the change twice. Anything else, like a
  # server that turns the change down, is logged: trying again wouldn't help.
  def changing_server(description)
    @unrepeatable = false
    connect { |imap| yield imap }
  rescue Unreachable, *UNREACHABLE => error
    raise Unreachable, "Couldn't reach #{@account.imap_host} to #{description}: #{error.message}" unless @unrepeatable
    Rails.logger.error("Failed to #{description}: #{error.message}")
  rescue StandardError => error
    Rails.logger.error("Failed to #{description}: #{error.message}")
  end

  # What comes next may reach the server even when the connection breaks, and would be
  # done twice by trying again
  def unrepeatable!
    @unrepeatable = true
  end

  def connect
    begin
      RemoteHost.verify!(@account.imap_host)
    rescue RemoteHost::LookupFailed => e
      raise Unreachable, e.message
    rescue RemoteHost::Forbidden => e
      raise ConnectionError, e.message
    end

    ssl_options = if @account.imap_ssl
      {
        verify_mode: OpenSSL::SSL::VERIFY_PEER
      }
    else
      false
    end

    imap = Net::IMAP.new(
      @account.imap_host,
      port: @account.imap_port,
      ssl: ssl_options
    )

    begin
      begin
        imap.login(@account.username, @account.password)
      rescue Net::IMAP::NoResponseError
        raise AuthenticationError, Mails::Account::AUTHENTICATION_FAILED
      end
      yield imap
    ensure
      imap.logout rescue nil
      imap.disconnect rescue nil
    end
  end

  # Every folder is synced the same way, whatever the age of its mail (except in very big folders): messages
  # gone from the server are removed, new ones fetched, and the flags of the most
  # recent ones refreshed, so read and starred changes made in other clients show up.
  def fetch_recent_emails(imap, folder_name, limit)
    server_uids = (imap.uid_search([ "ALL" ]) || []).sort
    reconcile_local_messages(folder_name, server_uids)

    existing_uids = @account.messages.where(folder: folder_name).where.not(uid: nil).pluck(:uid)
    new_uids = server_uids - existing_uids
    if server_uids.size > FULL_SYNC_MAX && !folder_name.in?(%w[INBOX Sent])
      new_uids &= imap.uid_search([ "SINCE", 3.months.ago.strftime("%d-%b-%Y") ]) || []
    end
    new_uids = new_uids.last(BACKFILL_BATCH)
    recent_existing = (server_uids & existing_uids).last(limit)
    uids = (new_uids + recent_existing).uniq.sort
    return if uids.empty?

    # No BODYSTRUCTURE: attachments are read from the full message. Some servers send
    # BODYSTRUCTUREs with NIL where a string belongs, and net-imap then drops the connection.
    uids.reverse.each_slice(FETCH_SLICE) do |slice|
      messages = imap.uid_fetch(slice, [ "UID", "ENVELOPE", "FLAGS", "INTERNALDATE", "BODY.PEEK[]" ])
      Array(messages).each { |msg| save_message(msg, folder_name) }
    end
  end

  # A message that can't be saved shouldn't keep the rest of its folder, and after the inbox
  # the rest of the account, from syncing. It's tried again on the next sync.
  def save_message(msg, folder_name)
    incoming_message.save(msg, folder_name)
  rescue StandardError => error
    Rails.error.report(error, context: { mail_account_id: @account.id, folder: folder_name, uid: msg.attr["UID"] })
  end

  def reconcile_local_messages(folder_name, server_uids)
    # Remove local messages that no longer exist on the server in this folder.
    # Skip trashed/archived/draft rows — those are kept intentionally in other views.
    scope = @account.messages
      .where(folder: folder_name, archived: false)
      .where.not(uid: nil)
    # Mail in the server's trash is trashed here too, discarded drafts with it, and leaves when the server empties it
    scope = scope.where(trashed: false, draft: false) unless folder_name == Mails::Account::TRASH
    stale_uids = scope.pluck(:uid) - server_uids
    scope.where(uid: stale_uids).destroy_all if stale_uids.any?
  end

  # The email is already saved; a broken invite must not stop the rest of the batch from syncing.

  # Outlook sends invitations as an inline text/calendar part without a file name,
  # so they aren't saved as attachments

  # The parts a mail client lists as attachments: marked "attachment", or inline with a
  # file name (like pasted images). Parts without a disposition belong to the body.

  # Mail sent from here goes out over SMTP, and most servers don't keep a copy of that
  # (Gmail and Office 365 do). Sent mail that has no copy on the server yet gets one, so
  # other mail programs show it too. A copy the server made itself is found by its
  # Message-ID and not added again. Either way the mail gets the UID of the copy. Mail that
  # is still being sent waits until it has gone out.
  def file_sent_mail(imap, sent_folder)
    @account.messages.where(folder: "Sent", uid: nil, draft: false, sending: false, trashed: false, archived: false).find_each do |message|
      uid = find_by_message_id(imap, message.message_id).last
      unless uid
        imap.append(sent_folder, build_raw_email(message), [ :Seen ], message.sent_at || Time.current)
        uid = find_by_message_id(imap, message.message_id).last
      end
      message.update_column(:uid, uid) if uid
    rescue Net::IMAP::Error, ActiveStorage::FileNotFoundError => e
      Rails.logger.warn("Could not file sent email #{message.id} on the server: #{e.class}: #{e.message}")
    end
  end

  # A search matches parts of a header, so it's done with the angle brackets: only this whole Message-ID matches
  def find_by_message_id(imap, message_id)
    imap.uid_search([ "HEADER", "Message-ID", "<#{message_id.delete("<>")}>" ]) || []
  end

  def find_sent_folder(imap)
    find_special_folder(imap.list("", "*"), "Sent")
  end

  def select_folder(imap, folder)
    imap.select(server_folder_names(imap, folder).first)
  end

  # A plain EXPUNGE removes every message flagged \Deleted in the folder, also ones another
  # mail client flagged without removing them. UID EXPUNGE removes only these messages.
  def remove_from_folder(imap, uids)
    imap.uid_store(uids, "+FLAGS", [ :Deleted ])

    if imap.capable?("UIDPLUS") || imap.capable?("IMAP4rev2")
      imap.uid_expunge(uids)
    else
      imap.expunge
    end
  end

  # Sent mail and drafts are kept in "Sent" and "Drafts" here, whatever the server calls
  # those folders ("[Gmail]/Sent Mail", "INBOX.Drafts", ...). Lists the server's folders at most once.
  def server_folder_names(imap, *folders)
    mailboxes = imap.list("", "*") if folders.intersect?(SPECIAL_FOLDERS.keys)
    folders.map { |folder| (mailboxes && find_special_folder(mailboxes, folder)) || folder }
  end

  # Mail synced from a special folder before it was known as one (like iCloud's "Deleted
  # Messages", synced as a folder of its own before the trash was) moves under its name here
  def adopt_special_folder(server_name, folder)
    return if server_name == folder

    earlier = @account.messages.where(folder: server_name)
    return unless earlier.exists?

    earlier.where(message_id: @account.messages.where(folder: folder).select(:message_id)).delete_all
    earlier.update_all(folder: folder, **(folder == Mails::Account::TRASH ? { trashed: true, trashed_at: Time.current } : {}))
  end

  # An account without an archive folder of its own archives to the server's. Mail archived
  # before that moves there too, or other mail programs keep showing it in the inbox.
  def adopt_archive_folder(mailboxes)
    return if @account.archive_folder.present?
    archive_folder = find_folder(mailboxes, *ARCHIVE_FOLDER) or return

    @account.update!(archive_folder: archive_folder)
    @account.messages.archived.not_trashed.not_draft.where(folder: "INBOX").where.not(uid: nil).find_each do |message|
      ImapSyncJob.perform_later(@account.id, "move_to_folder", message.uid, "INBOX", archive_folder)
    end
  end

  def find_special_folder(mailboxes, folder)
    attribute, names = SPECIAL_FOLDERS[folder]
    find_folder(mailboxes, attribute, names) if attribute
  end

  # The folder the server marks with the SPECIAL-USE attribute (RFC 6154),
  # or else the first one with a name servers commonly use
  def find_folder(mailboxes, attribute, names)
    mailboxes.find { |mailbox| mailbox.attr.include?(attribute) }&.name ||
      names.find { |name| mailboxes.any? { |mailbox| mailbox.name == name } }
  end

  def build_raw_email(message)
    mail = Mail.new
    mail.message_id = message.message_id
    mail.from = message.from_name.present? ? Mail::Address.new(message.from_address).tap { |address| address.display_name = message.from_name }.to_s : message.from_address
    mail.to = JSON.parse(message.to_addresses || "[]")
    mail.cc = JSON.parse(message.cc_addresses || "[]") if message.cc_addresses.present?
    mail.subject = message.subject
    mail.date = message.sent_at || Time.current
    mail.in_reply_to = message.in_reply_to if message.in_reply_to.present?
    mail.references = message.references if message.references.present?

    attachments = message.attachments.select { |attachment| attachment.file.attached? }
    # Pictures shown in the text by their Content-ID (a sent quote's) go inline, like a draft's quote
    pictures, files = attachments.partition { |attachment| attachment.content_id.present? }
    quote = Mails::Quote.of(message)
    inline_images = pictures.map { |picture| picture.slice(:filename, :content_type, :content_id).symbolize_keys.merge(content: picture.file.download) }
    inline_images += quote.inline_images if quote
    html = message.outgoing_html
    text = quote ? Mails::PlainText.from_html(html) : message.body_plain

    if html.present?
      # A forwarded draft carries the attachments it will be sent with, next to the text and HTML
      if files.any? || inline_images.any?
        mail.part(content_type: "multipart/alternative") { |alternative| add_text_and_html(alternative, html, text) }
      else
        add_text_and_html(mail, html, text)
      end
    elsif files.any?
      mail.text_part = Mail::Part.new(content_type: "text/plain; charset=UTF-8", body: message.body_plain || "")
    else
      mail.body = message.body_plain || ""
      mail.content_type = "text/plain; charset=UTF-8"
    end

    files.each do |attachment|
      mail.add_file(filename: attachment.filename, content: attachment.file.download, content_type: attachment.content_type.presence || "application/octet-stream")
    end
    Mails::Quote.add_inline_images(mail, inline_images) if html.present?

    mail.to_s
  end

  def add_text_and_html(mail, html, text)
    # Styled like sent mail, so other mail programs show the draft the way the editor does
    mail.html_part = Mail::Part.new(content_type: "text/html; charset=UTF-8", body: Mails::OutgoingHtml.from(html))
    mail.text_part = Mail::Part.new(content_type: "text/plain; charset=UTF-8", body: text) if text.present?
  end
end
