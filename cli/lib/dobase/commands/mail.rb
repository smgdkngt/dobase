# frozen_string_literal: true

require "shellwords"

module Dobase
  module Commands
    class Mail < Command
      VIEWS = { "inbox" => "Inbox", "drafts" => "Drafts", "starred" => "Starred", "sent" => "Sent", "archive" => "Archive", "trash" => "Trash" }.freeze
      EMAIL_FLAGS = {
        to: [ "ADDRS", "Recipients, comma-separated" ],
        cc: [ "ADDRS", "Cc recipients, comma-separated" ],
        subject: [ "TEXT", "Subject" ],
        body: [ "TEXT", "Message (plain text, or HTML with --html)" ],
        html: [ nil, "The body is HTML" ]
      }.freeze

      noun "mail", "Email in mail tools: conversations, flags, drafts and sending"

      command "mail list", "List the conversations in a folder (inbox unless --folder)", args: %w[TOOL],
        flags: {
          folder: [ "FOLDER", "#{VIEWS.keys.join(", ")} or a custom folder" ],
          search: [ "QUERY", "Only conversations whose subject, sender or text matches" ],
          page: [ "N", "Page (30 conversations per page)" ]
        } do |ref, folder: nil, search: nil, page: nil|
        mail_tool = tool(ref, "mail")
        mailbox = get("/tools/#{mail_tool["id"]}/mails", folder: folder, q: search, page: page)

        output(mailbox) do
          say "#{mail_tool["name"]} (mail #{mail_tool["id"]}) #{mailbox.dig("account", "email_address")}"
          say "#{VIEWS.fetch(mailbox["folder"], mailbox["folder"])}#{" matching #{quoted(search)}" if search}: " \
            "#{count(mailbox["total_count"], "conversation")}, page #{mailbox["page"]} of #{[ mailbox["total_pages"], 1 ].max}"
          say
          say "  (no conversations)" if mailbox["conversations"].empty?
          table(mailbox["conversations"].map { |conversation|
            [ "#{mail_tool["id"]}/#{conversation["id"]}", moment(conversation["sent_at"]), conversation["draft"] ? "Draft" : conversation["from"],
              conversation["subject"], conversation_summary(conversation) ]
          })

          if mailbox["page"] < mailbox["total_pages"]
            say
            options = { folder: folder, search: search, page: mailbox["page"] + 1 }.compact.map { |flag, value| "--#{flag} #{Shellwords.escape(value.to_s)}" }
            say "More: dobase mail list #{mail_tool["id"]} #{options.join(" ")}"
          end
          say
          say "Folders: #{folder_summary(mailbox)}"
        end
      end

      command "mail show", "Show a conversation: every message in it, oldest first", args: %w[TOOL/MESSAGE],
        flags: { html: [ nil, "Print the HTML of each message instead of its text" ] } do |ref, html: false|
        mail_tool, id = tool_and_id(ref, "mail", "message")
        conversation = get("/tools/#{mail_tool["id"]}/mails/#{id}")

        output(conversation) do
          say "#{conversation["subject"]} (#{count(conversation["messages"].size, "message")})"

          conversation["messages"].each do |message|
            say
            say "[#{mail_tool["id"]}/#{message["id"]}] #{address(message["from_name"], message["from_address"])} · #{moment(message["sent_at"])}"
            field "To", message["to"].join(", ")
            field "Cc", message["cc"].join(", ")
            field "Subject", message["subject"]
            field "Status", message_status(message)
            field "URL", message["url"]
            say

            body = html ? message["body_html"] : message["body"]
            body.to_s.strip.empty? ? say("  (no #{html ? "HTML" : "text"})") : paragraph(body)

            unless message["attachments"].empty?
              say
              say "  Attachments:"
              table(message["attachments"].map { |attachment| [ attachment["filename"], bytes(attachment["file_size"]), attachment["download_url"] ] }, indent: 4)
            end

            message["calendar_invites"].each do |invite|
              say
              say "  Invitation: #{invite["summary"]}, #{moment(invite["starts_at"])} to #{moment(invite["ends_at"])}" \
                "#{", #{invite["location"]}" unless invite["location"].to_s.empty?} (#{invite["status"]})"
            end
          end
        end
      end

      command "mail read", "Mark a message as read, here and on the mail server", args: %w[TOOL/MESSAGE] do |ref|
        change_message(ref, :post, "read") { |message| "Marked #{message} as read." }
      end

      command "mail unread", "Mark a message as unread, here and on the mail server", args: %w[TOOL/MESSAGE] do |ref|
        change_message(ref, :delete, "read") { |message| "Marked #{message} as unread." }
      end

      command "mail star", "Star a message (flagged on the mail server)", args: %w[TOOL/MESSAGE] do |ref|
        change_message(ref, :post, "star") { |message| "Starred #{message}." }
      end

      command "mail unstar", "Remove the star from a message", args: %w[TOOL/MESSAGE] do |ref|
        change_message(ref, :delete, "star") { |message| "Unstarred #{message}." }
      end

      command "mail archive", "Archive a message (moved to the account's archive folder on the server, if it has one)", args: %w[TOOL/MESSAGE] do |ref|
        change_message(ref, :post, "archive") { |message| "Archived #{message}." }
      end

      command "mail unarchive", "Move an archived message back to the inbox", args: %w[TOOL/MESSAGE] do |ref|
        change_message(ref, :delete, "archive") { |message| "Unarchived #{message}." }
      end

      command "mail move", "Move a message to another folder on the mail server: INBOX, Sent or a custom folder", args: %w[TOOL/MESSAGE FOLDER] do |ref, folder|
        # `mail list` shows views in lowercase; moving needs the folder names the server uses.
        folder = "INBOX" if folder.casecmp?("inbox")
        folder = "Sent" if folder == "sent"
        if %w[drafts starred archive trash].include?(folder)
          hint = { "starred" => "star", "archive" => "archive" }[folder]
          raise UsageError, "#{folder} is a view, not a folder#{"; use `dobase mail #{hint}`" if hint}. " \
            "Move to INBOX, Sent or a custom folder (see `dobase mail list`)."
        end

        mail_tool, id = tool_and_id(ref, "mail", "message")
        message = post("/tools/#{mail_tool["id"]}/mails/#{id}/move", folder: folder)
        output(message) { say "Moved #{describe(mail_tool, message)} to #{message["folder"]}." }
      end

      command "mail draft", "Save a new draft (nothing is sent; it is copied to the server's Drafts folder)", args: %w[TOOL],
        flags: EMAIL_FLAGS do |ref, to: nil, cc: nil, subject: nil, body: nil, html: false|
        require_flags(to: to, subject: subject, body: body)
        mail_tool = tool(ref, "mail")

        draft = post("/tools/#{mail_tool["id"]}/mails/drafts", to: to, cc: cc, subject: text(subject), body: rich_text(body, html: html))
        output(draft) { say "Saved draft #{describe(mail_tool, draft)} to #{draft["to"].join(", ")}. Send it with: dobase mail send #{mail_tool["id"]} --draft #{draft["id"]}" }
      end

      command "mail reply", "Reply to a message: saves a draft, or sends real email right away with --send", args: %w[TOOL/MESSAGE],
        flags: {
          body: [ "TEXT", "Your reply (plain text, or HTML with --html)" ],
          all: [ nil, "Reply to all: cc everyone else on the message" ],
          html: [ nil, "The body is HTML" ],
          send: [ nil, "Send it now through the mail server instead of saving a draft" ]
        } do |ref, body: nil, all: false, html: false, send: false|
        require_flags(body: body)
        mail_tool, id = tool_and_id(ref, "mail", "message")
        conversation = get("/tools/#{mail_tool["id"]}/mails/#{id}")
        original = conversation["messages"].find { |message| message["id"] == id }
        raise Error, "#{mail_tool["id"]}/#{id} is a draft. Send it with: dobase mail send #{mail_tool["id"]} --draft #{id}" if original["draft"]

        to, cc = reply_recipients(original, conversation.dig("account", "email_address"), all: all)
        raise Error, "#{mail_tool["id"]}/#{id} has no address to reply to." if to.empty?

        reply = { to: to.join(", "), cc: cc.join(", "), subject: "Re: #{original["subject"].to_s.sub(/\A(Re|Fwd|Fw):\s*/i, "").strip}", body: rich_text(body, html: html) }
        if send
          sent = post("/tools/#{mail_tool["id"]}/mails", reply)
          output(sent) { say "Sent #{quoted(sent["subject"])} to #{recipients(sent)}." }
        else
          draft = post("/tools/#{mail_tool["id"]}/mails/drafts", reply.merge(in_reply_to: original["message_id"]))
          output(draft) { say "Saved reply draft #{describe(mail_tool, draft)} to #{recipients(draft)}. Send it with: dobase mail send #{mail_tool["id"]} --draft #{draft["id"]}" }
        end
      end

      command "mail send", "Send real email now through the mail server; --draft ID sends a saved draft as it is", args: %w[TOOL],
        flags: {
          to: EMAIL_FLAGS[:to], cc: EMAIL_FLAGS[:cc], bcc: [ "ADDRS", "Bcc recipients, comma-separated" ],
          subject: EMAIL_FLAGS[:subject], body: EMAIL_FLAGS[:body], html: EMAIL_FLAGS[:html],
          draft: [ "ID", "Send this saved draft instead (it leaves Drafts)" ]
        } do |ref, draft: nil, **email|
        mail_tool = tool(ref, "mail")

        if draft
          raise UsageError, "--draft sends the draft as it is saved; leave out --to, --cc, --bcc, --subject, --body and --html." if email.any?
          draft_id = draft[/\A(?:.+\/)?(\d+)\z/, 1]
          raise UsageError, "--draft expects a draft id like 21, got #{quoted(draft)}." unless draft_id

          saved = get("/tools/#{mail_tool["id"]}/mails/#{draft_id}")["messages"].find { |message| message["id"] == draft_id.to_i }
          raise Error, "#{mail_tool["id"]}/#{draft_id} is not a draft." unless saved["draft"]
          raise Error, "Draft #{mail_tool["id"]}/#{draft_id} has no recipients." if saved["to"].empty?

          body = saved["body_html"] || CGI.escapeHTML(saved["body"].to_s)
          request = { to: saved["to"].join(", "), cc: saved["cc"].join(", "), subject: saved["subject"], body: body, draft_id: saved["id"] }
        else
          require_flags(to: email[:to], subject: email[:subject], body: email[:body])
          request = { to: email[:to], cc: email[:cc], bcc: email[:bcc], subject: text(email[:subject]), body: rich_text(email[:body], html: email[:html]) }
        end

        sent = post("/tools/#{mail_tool["id"]}/mails", request)
        output(sent) { say "Sent #{quoted(sent["subject"])} to #{recipients(sent)}." }
      end

      command "mail sync", "Fetch new mail from the mail server now (runs in the background)", args: %w[TOOL] do |ref|
        mail_tool = tool(ref, "mail")
        status = post("/tools/#{mail_tool["id"]}/sync")
        output(status) { say "Syncing #{mail_tool["name"]} (mail #{mail_tool["id"]}) in the background. Last synced: #{moment(status["last_synced_at"]) || "never"}." }
      end

      command "mail contacts", "Find addresses you've mailed or received mail from", args: %w[TOOL QUERY] do |ref, query|
        raise UsageError, "QUERY needs at least 2 characters." if query.strip.length < 2

        mail_tool = tool(ref, "mail")
        contacts = get("/tools/#{mail_tool["id"]}/mails_contacts", q: query.strip)
        output(contacts) do
          say "Nobody matches #{quoted(query)}." if contacts.empty?
          contacts.each { |contact| say address(contact["name"], contact["email_address"]) }
        end
      end

      private

      def change_message(ref, method, action)
        mail_tool, id = tool_and_id(ref, "mail", "message")
        path = "/tools/#{mail_tool["id"]}/mails/#{id}/#{action}"
        message = method == :post ? post(path) : delete(path)
        output(message) { say yield(describe(mail_tool, message)) }
      end

      def require_flags(**flags)
        missing = flags.select { |_flag, value| value.nil? }.keys
        raise UsageError, "Missing #{missing.map { |flag| "--#{flag}" }.join(", ")}. See `dobase help mail`." if missing.any?
      end

      # Like other mail clients, a reply to a message you sent goes to its recipients.
      def reply_recipients(message, own_address, all:)
        own = ->(address) { address.to_s.casecmp?(own_address.to_s) }
        to = own.(message["from_address"]) ? message["to"] : [ message["from_address"] ].compact
        cc = all ? (message["to"] + message["cc"]).reject { |address| own.(address) || to.any? { |recipient| recipient.casecmp?(address) } } : []
        [ to, cc.uniq(&:downcase) ]
      end

      def describe(mail_tool, message)
        "#{mail_tool["id"]}/#{message["id"]} #{message["subject"].to_s.empty? ? "(no subject)" : quoted(message["subject"])}"
      end

      def address(name, email)
        name.to_s.empty? ? email.to_s : "#{name} <#{email}>"
      end

      def recipients(email)
        [ email["to"].join(", "), ("cc #{email["cc"].join(", ")}" if email["cc"]&.any?), ("bcc #{email["bcc"].join(", ")}" if email["bcc"]&.any?) ].compact.join("; ")
      end

      def conversation_summary(conversation)
        [
          ("unread" unless conversation["read"]),
          ("starred" if conversation["starred"]),
          (count(conversation["messages_count"], "message") if conversation["messages_count"] > 1),
          ("attachments" if conversation["has_attachments"])
        ].compact.join("  ")
      end

      def message_status(message)
        [
          ("draft" if message["draft"]),
          (message["read"] ? "read" : "unread"),
          ("starred" if message["starred"]),
          ("archived" if message["archived"]),
          ("in trash" if message["trashed"]),
          ("folder #{message["folder"]}" unless message["draft"])
        ].compact.join(", ")
      end

      def folder_summary(mailbox)
        counts = { "inbox" => [ mailbox.dig("counts", "inbox_unread"), "unread" ], "drafts" => [ mailbox.dig("counts", "drafts"), nil ], "trash" => [ mailbox.dig("counts", "trash"), nil ] }
        names = mailbox["folders"].map do |name|
          number, label = counts[name]
          number.to_i.positive? ? "#{name} (#{[ number, label ].compact.join(" ")})" : name
        end
        (names + mailbox["custom_folders"]).join(", ")
      end
    end
  end
end
