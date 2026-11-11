# frozen_string_literal: true

module Tools
  class MailsController < ApplicationController
    include ToolScoped
    include NextMailNavigation

    # The compose form and deleting mail for good stay in the browser.
    allow_access_tokens only: %i[index show create]
    restrict_in_demo only: :create
    before_action :require_mail_account
    before_action :set_message, only: [ :show, :destroy ]
    before_action :build_compose_defaults, only: [ :new ]

    PER_PAGE = 30
    DRAFT_GONE = "This draft was already sent or deleted elsewhere, so it wasn't sent again. Send it once more to send it as new mail."

    def index
      @mail_account = @tool.mail_account
      # A folder of the account's own is asked for by the server's name or by the one it shows under
      @current_folder = @mail_account.custom_folder_shown_as(params[:folder]) || params[:folder] || "inbox"
      load_index_data
    end

    def show
      respond_to do |format|
        format.html do
          # A discarded draft is read in the trash, like other mail there
          if @message.draft? && !@message.trashed?
            redirect_to new_tool_mail_path(@tool, draft_id: @message.id)
          else
            @selected_message = @message
            @current_folder = params[:folder] || "inbox"
            # A discarded draft is out of its conversation: it only shows when it's opened from the trash
            @conversation_messages = @message.conversation_without_copies.reject { |message| message.draft? && message.trashed? && message != @message }
            unread = @message.conversation.unread.to_a
            unread.each(&:mark_as_read!)
            # Read here is read in every window that has this mailbox open
            announce_a_change if unread.any?
            # Read by now, which is what its "Mark unread" button goes by
            @message.reload if unread.any?

            unless turbo_frame_request?
              load_index_data
              render :index
            end
          end
        end
        # Reading through the API leaves the conversation unread; it has its own read endpoints.
        format.json do
          @conversation_messages = @message.conversation_without_copies(@message.conversation.includes(:calendar_invites, attachments: { file_attachment: :blob }))
        end
      end
    end

    def new
      @mail_account = @tool.mail_account

      if params[:draft_id].present?
        @draft = @mail_account.messages.drafts.find_by(id: params[:draft_id])
      elsif params[:reply_to].present?
        original = @mail_account.messages.find_by(id: params[:reply_to])
        @draft = @mail_account.messages.drafts.find_by(in_reply_to: original.message_id) if original
      end

      if @draft
        @to = @draft.to_addresses_list.join(", ")
        @cc = @draft.cc_addresses_list.join(", ")
        @bcc = @draft.bcc_addresses_list.join(", ")
        @subject = @draft.subject || ""
        @body = @draft.body_html || @draft.body_plain || ""
        @in_reply_to = @draft.in_reply_to
        @forward_attachments = @draft.attachments.select { |attachment| attachment.file.attached? }
        @quoted_message = @draft.quoted_message
        @quote_html = @draft.quote_html
      end

      render_compose
    end

    def create
      @mail_account = @tool.mail_account

      recipients = %i[to cc bcc].index_with { |field| ::Mails::Recipient.parse(params[field]) }
      invalid = recipients.values.flatten.reject(&:valid?)

      if invalid.any?
        render_send_error "Invalid email address: #{invalid.first.address}"
        return
      end

      # A draft sent or deleted elsewhere (another window, the CLI) while this form was open
      # isn't sent a second time: the form comes back, without the draft, to send as new mail
      if params[:draft_id].present? && !@mail_account.messages.drafts.exists?(id: params[:draft_id])
        render_send_error DRAFT_GONE
        return
      end

      # The mail is kept by its addresses; the names go out with it from what the account knows
      @mail_account.remember_names(recipients.values.flatten)
      to = recipients[:to].map(&:address)
      cc = recipients[:cc].map(&:address).presence
      bcc = recipients[:bcc].map(&:address).presence

      # From the compose page the mail goes out in the background, so the page doesn't wait
      # for the mail server: it opens the conversation, with the mail in it. The API sends it
      # right away, to say whether it went.
      if request.format.json?
        send_now(to: to, cc: cc, bcc: bcc)
      else
        message = outgoing_draft(to: to, cc: cc, bcc: bcc)
        message.start_sending!
        SendMailJob.perform_later(message, Current.user)
        folder = params[:folder].presence || "inbox"
        redirect_to tool_mail_path(@tool, opened_in_folder(message, folder), folder: folder)
      end
    end

    def destroy
      if @message.draft?
        @tool.mail_account.discard(@message)
        # Discarded where it shows in its conversation, the conversation stays open
        answered = @message.conversation.not_draft.last if params[:from] == "conversation"
        redirect_to answered ? tool_mail_path(@tool, answered, folder: params[:folder]) : tool_mails_path(@tool, folder: "drafts"), notice: "Draft deleted."
        return
      end

      folder = params[:folder] || (@message.trashed? ? "trash" : "inbox")
      next_msg = find_next_message(@message, folder)
      if @message.trashed?
        @tool.mail_account.delete_for_good(with_their_conversations([ @message ], folder: "trash"))
        redirect_to_next_mail_or_fallback(next_msg, folder: folder, notice: "Email permanently deleted.")
      else
        @tool.mail_account.trash(with_their_conversations([ @message ], folder: folder))
        redirect_to_next_mail_or_fallback(next_msg, folder: folder, notice: "Email moved to trash.")
      end
    end

    private

    # Owners connect the account; everyone else waits for them
    def require_mail_account
      return if @tool.mail_account

      respond_to do |format|
        format.html do
          if @tool.owned_by?(current_user)
            redirect_to new_tool_mails_account_path(@tool)
          else
            render "tools/account_not_connected"
          end
        end
        format.json { render_mail_account_not_configured }
      end
    end

    def render_mail_account_not_configured
      render json: { error: "Mail account not configured" }, status: :not_found
    end

    def render_send_error(message)
      respond_to do |format|
        format.html do
          flash.now[:alert] = message
          build_compose_defaults
          # Still the draft it was, with the attachments it forwards
          @draft = @mail_account.messages.drafts.find_by(id: params[:draft_id]) if params[:draft_id].present?
          @forward_attachments = @mail_account.attachments.where(id: params[:forward_attachment_ids]).select { |attachment| attachment.file.attached? } if params[:forward_attachment_ids].present?
          @quoted_message = quoted_message_param
          # What was changed in the quote is still changed
          @quote_html = @mail_account.messages.new(quote_html: params[:quote_html]).quote_html
          @unsent = true
          render_compose status: :unprocessable_entity
        end
        format.json { render json: { errors: [ message ] }, status: :unprocessable_entity }
      end
    end

    # The message is written in the reading pane, next to the folder it was started from
    def render_compose(status: :ok)
      @composing = true
      @heading = "Edit Draft" if @draft
      @current_folder = params[:folder] || "inbox"
      load_index_data
      render :index, status: status
    end

    def set_message
      @mail_account = @tool.mail_account
      @message = @mail_account.messages.find(params[:id])
    end

    def load_index_data
      @inbox_unread = @mail_account.messages.inbox.not_archived.unread.count
      @trash_count = @mail_account.messages.trashed.count
      @junk_unread = @mail_account.messages.junk.unread.count if @mail_account.junk_folder?
      @drafts_count = @mail_account.messages.drafts.count
      @custom_folders = @mail_account.custom_folders

      if params[:q].present?
        # A search looks in every folder but the trash and junk, unless it is told one (`in`)
        @searching_in = params[:in].presence || "all"
        @sort = params[:sort] == "date" ? "date" : "relevance"
        scope = @searching_in == "all" ? @mail_account.messages.not_trashed.not_draft.where.not(folder: ::Mails::Account::JUNK) : mail_folder_scope(@searching_in)
        @conversations = fetch_conversations(scope.search(params[:q]), ranked: @sort == "relevance")
      else
        @conversations = fetch_conversations(mail_folder_scope(@current_folder))
      end
    end

    # A page of conversations. The folder's threads are summed up in one query and
    # paginated, and only the messages of the threads on the page are loaded. Search
    # results come best match first when `ranked`.
    def fetch_conversations(scope, ranked: false)
      threads = thread_summaries(scope, ranked: ranked)

      @total_count = threads.size
      @total_pages = (@total_count / PER_PAGE.to_f).ceil
      @page = (params[:page] || 1).to_i.clamp(1, [ @total_pages, 1 ].max)

      threads = threads.slice((@page - 1) * PER_PAGE, PER_PAGE) || []
      # Sorted here: ordered by date in SQL, SQLite walks the whole folder by its date
      # index and opens every row to find the threads on this page
      messages = scope.where(thread_id: threads.map(&:thread_id)).select(*list_columns)
        .sort_by { |message| message.sent_at || Time.at(0) }.reverse.group_by(&:thread_id)

      threads.filter_map do |thread|
        thread_messages = messages[thread.thread_id]
        latest = thread_messages&.first
        next unless latest

        {
          id: latest.id,
          thread_id: thread.thread_id,
          subject: latest.normalized_subject.presence || "(No subject)",
          from: latest.display_from,
          from_address: latest.from_address,
          preview: latest.preview,
          sent_at: latest.sent_at,
          read: thread.unread_count.zero?,
          starred: thread.starred,
          has_attachments: thread.has_attachments,
          count: thread.count,
          unread_count: thread.unread_count,
          draft: latest.draft? && !latest.trashed?,
          folder: @mail_account.view_of(latest),
          participants: thread_messages.map { |message| [ message.from_name, message.from_address ] }.uniq.map { |name, address| name.presence || address }.first(3)
        }
      end
    end

    # What the list shows of a message: no bodies, which can be hundreds of kilobytes
    # each, but the start of its text for the preview
    def list_columns
      [
        *(::Mails::Message.column_names - %w[body_html body_plain quote_html]).map { |column| "mail_messages.#{column}" },
        Arel.sql("substr(mail_messages.body_plain, 1, 1000) AS body_plain")
      ]
    end

    # A message by its Message-ID, so its copies in other folders are one; mail without one by its row
    MESSAGE = "COALESCE(mail_messages.message_id, 'row-' || mail_messages.id)"

    ThreadSummary = Data.define(:thread_id, :latest_at, :count, :unread_count, :starred, :has_attachments, :score)

    # One row per thread in the folder, newest first. The flags match the
    # unread, starred and with_attachments scopes.
    def thread_summaries(scope, ranked: false)
      rows = scope.group(:thread_id).pluck(
        :thread_id,
        Arel.sql("MAX(mail_messages.sent_at)"),
        # A message in two folders on the server, like the archive's, counts once
        Arel.sql("COUNT(DISTINCT mail_messages.message_id)"),
        # Unread is a message none of whose copies is read: mail archived here and read
        # since has an older, unread copy in the archive folder, which isn't shown
        Arel.sql("COUNT(DISTINCT #{MESSAGE}) - COUNT(DISTINCT CASE WHEN mail_messages.read = 1 THEN #{MESSAGE} END)"),
        Arel.sql("MAX(CASE WHEN mail_messages.starred = 1 AND mail_messages.trashed = 0 AND mail_messages.draft = 0 THEN 1 ELSE 0 END)"),
        Arel.sql("MAX(CASE WHEN mail_messages.has_attachments = 1 THEN 1 ELSE 0 END)"),
        # How well its best message matched a search (lower is better), nothing otherwise
        Arel.sql(ranked ? "MIN(mail_hits.hit_score)" : "NULL")
      )

      threads = rows.map { |thread_id, latest_at, count, unread, starred, attachments, score| ThreadSummary.new(thread_id, latest_at, count, unread.to_i, starred == 1, attachments == 1, score) }
        .sort_by { |thread| thread.latest_at.to_s }.reverse
      ranked ? threads.sort_by.with_index { |thread, newest| [ thread.score, newest ] } : threads
    end

    def build_compose_defaults
      @to = params[:to] || ""
      @cc = params[:cc] || ""
      @bcc = params[:bcc] || ""
      @subject = params[:subject] || ""
      @body = params[:body] || ""
      @in_reply_to = params[:in_reply_to]
      @heading = @in_reply_to.present? ? "Reply" : "New Message"

      if params[:reply_to].present?
        original = @tool.mail_account.messages.find_by(id: params[:reply_to])
        if original
          @heading = params[:reply_all] ? "Reply All" : "Reply"
          @composing_from = original
          @in_reply_to = original.message_id
          @subject = "Re: #{original.normalized_subject}" unless @subject.present?
          @quoted_message = original

          # A reply to mail of your own, like the one just sent, goes to the people it went to
          if original.from_address.to_s.casecmp?(@tool.mail_account.email_address)
            @to = original.to_addresses_list.join(", ")
            others = original.cc_addresses_list
          else
            @to = original.from_address
            others = original.to_addresses_list + original.cc_addresses_list - [ @to ]
          end
          # Mail synced before group names were left out ("undisclosed-recipients:;") has them as addresses without a host
          others = others.reject { |address| address.end_with?("@") }
          @cc = (others - [ @tool.mail_account.email_address ]).join(", ") if params[:reply_all]
        end
      elsif params[:forward].present?
        original = @tool.mail_account.messages.find_by(id: params[:forward])
        if original
          @heading = "Forward"
          @composing_from = original
          @subject = "Fwd: #{original.normalized_subject}" unless @subject.present?
          @quoted_message = original
          # The pictures in its text go along with the quote
          @forward_attachments = original.listed_attachments.select { |attachment| attachment.file.attached? }
        end
      end
    end

    def send_now(to:, cc:, bcc:)
      draft = @mail_account.messages.drafts.find_by(id: params[:draft_id]) if params[:draft_id].present?
      message = @mail_account.messages.new(body_html: params[:body], in_reply_to: params[:in_reply_to].presence,
        quoted_message: quoted_message_param, quote_html: quote_html_param(draft))
      quote = ::Mails::Quote.of(message)
      body_html = message.outgoing_html
      attachments = Array(params[:attachments])
      # Forwarded attachments (Active Storage blobs), only from this account's own mail. The
      # pictures in a quote's text go along with the quote.
      if params[:forward_attachment_ids].present?
        @mail_account.attachments.where(id: params[:forward_attachment_ids]).where.not(id: quote&.image_ids).each do |attachment|
          attachments << attachment.file.blob if attachment.file.attached?
        end
      end

      SmtpSendService.new(@mail_account).send_email(
        to: to, cc: cc, bcc: bcc, subject: params[:subject],
        body: ::Mails::PlainText.from_html(body_html, links: true), body_html: body_html,
        attachments: attachments.presence, inline_images: quote&.inline_images.presence, in_reply_to: params[:in_reply_to].presence,
        quoted: message.quoted_message
      )
      remove_sent_draft(draft)

      render json: { to: to, cc: cc.to_a, bcc: bcc.to_a, subject: params[:subject] }, status: :created
    rescue SmtpSendService::SendError => e
      render_send_error e.message
    end

    # What the compose page sends is saved as the draft it was or would have been, so mail
    # that can't be sent is still there to try again
    def outgoing_draft(to:, cc:, bcc:)
      draft = @mail_account.messages.drafts.find_by(id: params[:draft_id]) || @mail_account.new_draft
      draft.assign_attributes(
        to_addresses: to.to_json, cc_addresses: cc&.to_json, bcc_addresses: bcc&.to_json,
        subject: params[:subject], body_html: params[:body], body_plain: ::Mails::PlainText.from_html(params[:body]),
        in_reply_to: params[:in_reply_to].presence, sent_at: Time.current
      )
      # The mail it quotes, and that quote as the form has it: changed, or as it was written
      if params.key?(:quoted_message_id)
        draft.quoted_message = quoted_message_param
        draft.quote_html = params[:quote_html]
      end
      # Files taken off in the form, before what is added (removing reloads the draft's files)
      draft.remove_attachments(params[:remove_attachment_ids]) if draft.persisted? && params[:remove_attachment_ids].present?
      # Forwarded attachments, only from this account's own mail; a saved draft already has its
      # own, and the pictures in a quote's text go along with the quote
      forwarded = @mail_account.attachments.where(id: params[:forward_attachment_ids]).where.not(mail_message_id: draft.id)
        .where.not(id: ::Mails::Quote.of(draft)&.image_ids) if params[:forward_attachment_ids].present?
      draft.copy_attachments(forwarded.includes(file_attachment: :blob)) if forwarded
      draft.attach_uploads(Array(params[:attachments])) if params[:attachments].present?
      draft.save!
      draft
    end

    # A conversation opens the way the folder's list opens it: on its last message in that
    # folder, which is what archiving and trashing then act on. Mail that isn't in a
    # conversation there opens by itself.
    def opened_in_folder(message, folder)
      mail_folder_scope(folder).where(thread_id: message.thread_id).order(sent_at: :desc).first || message
    end

    # The mail a reply or forward quotes below its text, only from this account's own mail
    def quoted_message_param
      @mail_account.messages.find_by(id: params[:quoted_message_id]) if params[:quoted_message_id].present?
    end

    # The quote as it was changed while writing. A client that sends a saved draft without
    # saying so (an older CLI) sends what was changed in that draft, not the mail as it was.
    def quote_html_param(draft)
      return params[:quote_html] if params.key?(:quote_html)

      draft.quote_html if draft && draft.quoted_message_id.to_s == params[:quoted_message_id].to_s
    end

    # The draft that went out as this mail: it was sent, not thrown away
    def remove_sent_draft(draft)
      return unless draft

      ImapSyncJob.perform_later(@mail_account.id, "delete_draft", draft.uid, "Drafts") if draft.uid
      draft.destroy
    end
  end
end
