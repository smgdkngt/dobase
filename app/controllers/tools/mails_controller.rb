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

      to = params[:to].to_s.split(/,\s*/).reject(&:blank?)
      cc = params[:cc].presence&.split(/,\s*/)&.reject(&:blank?)
      bcc = params[:bcc].presence&.split(/,\s*/)&.reject(&:blank?)

      invalid = [ *to, *cc, *bcc ].reject { |recipient| valid_recipient?(recipient) }

      if invalid.any?
        render_send_error "Invalid email address: #{invalid.first}"
        return
      end

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
        ImapSyncJob.perform_later(@tool.mail_account.id, "delete_draft", @message.uid, "Drafts") if @message.uid
        @message.destroy
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

    # An address, or a name with an address: "Ann Lee <ann@example.com>"
    def valid_recipient?(recipient)
      Mail::Address.new(recipient).address.to_s.match?(URI::MailTo::EMAIL_REGEXP)
    rescue Mail::Field::ParseError
      false
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
      @drafts_count = @mail_account.messages.drafts.count
      @custom_folders = @mail_account.custom_folders

      base_scope = case @current_folder
      when "sent"    then @mail_account.messages.sent.not_archived
      when "starred" then @mail_account.messages.starred
      when "trash"   then @mail_account.messages.trashed
      when "drafts"  then @mail_account.messages.drafts
      when "archive" then @mail_account.archived_messages
      when "inbox"   then @mail_account.messages.inbox.not_archived
      else                @mail_account.messages.where(folder: @current_folder).not_archived.not_trashed.not_draft
      end

      base_scope = base_scope.search(params[:q]) if params[:q].present?
      @conversations = fetch_conversations(base_scope)
    end

    # A page of conversations. The folder's threads are summed up in one query and
    # paginated, and only the messages of the threads on the page are loaded.
    def fetch_conversations(scope)
      threads = thread_summaries(scope)

      @total_count = threads.size
      @total_pages = (@total_count / PER_PAGE.to_f).ceil
      @page = (params[:page] || 1).to_i.clamp(1, [ @total_pages, 1 ].max)

      threads = threads.slice((@page - 1) * PER_PAGE, PER_PAGE) || []
      messages = scope.where(thread_id: threads.map(&:thread_id)).order(sent_at: :desc).group_by(&:thread_id)

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
          participants: thread_messages.map { |message| [ message.from_name, message.from_address ] }.uniq.map { |name, address| name.presence || address }.first(3)
        }
      end
    end

    ThreadSummary = Data.define(:thread_id, :latest_at, :count, :unread_count, :starred, :has_attachments)

    # One row per thread in the folder, newest first. The flags match the
    # unread, starred and with_attachments scopes.
    def thread_summaries(scope)
      rows = scope.group(:thread_id).pluck(
        :thread_id,
        Arel.sql("MAX(mail_messages.sent_at)"),
        # A message in two folders on the server, like the archive's, counts once
        Arel.sql("COUNT(DISTINCT mail_messages.message_id)"),
        Arel.sql("SUM(CASE WHEN mail_messages.read = 0 THEN 1 ELSE 0 END)"),
        Arel.sql("MAX(CASE WHEN mail_messages.starred = 1 AND mail_messages.trashed = 0 AND mail_messages.draft = 0 THEN 1 ELSE 0 END)"),
        Arel.sql("MAX(CASE WHEN mail_messages.has_attachments = 1 THEN 1 ELSE 0 END)")
      )

      rows.map { |thread_id, latest_at, count, unread, starred, attachments| ThreadSummary.new(thread_id, latest_at, count, unread.to_i, starred == 1, attachments == 1) }
        .sort_by { |thread| thread.latest_at.to_s }.reverse
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
        body: ::Mails::PlainText.from_html(body_html), body_html: body_html,
        attachments: attachments.presence, inline_images: quote&.inline_images.presence, in_reply_to: params[:in_reply_to].presence
      )
      discard_draft(draft)

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

    def discard_draft(draft)
      return unless draft

      ImapSyncJob.perform_later(@mail_account.id, "delete_draft", draft.uid, "Drafts") if draft.uid
      draft.destroy
    end
  end
end
