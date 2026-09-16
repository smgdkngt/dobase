# frozen_string_literal: true

module Tools
  class MailsController < ApplicationController
    include ToolAuthorization
    include NextMailNavigation

    # The compose form and deleting mail for good stay in the browser.
    allow_access_tokens only: %i[index show create]

    before_action :set_tool
    before_action -> { authorize_tool_access!(@tool) }
    before_action :require_mail_account
    before_action :set_message, only: [ :show, :destroy ]
    before_action :build_compose_defaults, only: [ :new ]

    PER_PAGE = 30

    def index
      @mail_account = @tool.mail_account
      @current_folder = params[:folder] || "inbox"
      load_index_data
    end

    def show
      respond_to do |format|
        format.html do
          if @message.draft?
            redirect_to new_tool_mail_path(@tool, draft_id: @message.id)
          else
            @selected_message = @message
            @current_folder = params[:folder] || "inbox"
            @conversation_messages = @message.conversation.to_a
            @message.conversation.unread.find_each(&:mark_as_read!)

            unless turbo_frame_request?
              load_index_data
              render :index
            end
          end
        end
        # Reading through the API leaves the conversation unread; it has its own read endpoints.
        format.json do
          @conversation_messages = @message.conversation.includes(:calendar_invites, attachments: { file_attachment: :blob })
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
        @subject = @draft.subject || ""
        @body = @draft.body_html || @draft.body_plain || ""
        @in_reply_to = @draft.in_reply_to
      end
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

      body_html = params[:body]
      body_plain = ActionController::Base.helpers.strip_tags(body_html)&.gsub(/\s+/, " ")&.strip

      all_attachments = Array(params[:attachments])

      # Include forwarded attachments (Active Storage blobs), only from this account's own mail
      if params[:forward_attachment_ids].present?
        @mail_account.attachments.where(id: params[:forward_attachment_ids]).each do |att|
          all_attachments << att.file.blob if att.file.attached?
        end
      end

      service = SmtpSendService.new(@mail_account)
      service.send_email(
        to: to,
        cc: cc,
        bcc: bcc,
        subject: params[:subject],
        body: body_plain,
        body_html: body_html,
        attachments: all_attachments.presence,
        in_reply_to: params[:in_reply_to].presence
      )

      if params[:draft_id].present?
        draft = @mail_account.messages.drafts.find_by(id: params[:draft_id])
        if draft
          ImapSyncService.new(@mail_account).delete_draft(draft.uid)
          draft.destroy
        end
      end

      respond_to do |format|
        format.html { redirect_to tool_mails_path(@tool, folder: "sent"), notice: "Email sent successfully." }
        format.json { render json: { to: to, cc: cc.to_a, bcc: bcc.to_a, subject: params[:subject] }, status: :created }
      end
    rescue SmtpSendService::SendError => e
      render_send_error e.message
    end

    def destroy
      if @message.draft?
        ImapSyncService.new(@tool.mail_account).delete_draft(@message.uid)
        @message.destroy
        redirect_to tool_mails_path(@tool, folder: "drafts"), notice: "Draft deleted."
        return
      end

      folder = params[:folder] || (@message.trashed? ? "trash" : "inbox")
      next_msg = find_next_message(@message, folder)
      if @message.trashed?
        sync_delete_to_imap(@message)
        @message.destroy
        redirect_to_next_mail_or_fallback(next_msg, folder: folder, notice: "Email permanently deleted.")
      else
        @message.update(trashed: true)
        sync_delete_to_imap(@message)
        redirect_to_next_mail_or_fallback(next_msg, folder: folder, notice: "Email moved to trash.")
      end
    end

    private

    def set_tool
      @tool = Tool.find(params[:tool_id])
    end

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
          @unsent = true
          render :new, status: :unprocessable_entity
        end
        format.json { render json: { errors: [ message ] }, status: :unprocessable_entity }
      end
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
      when "sent"    then @mail_account.messages.sent
      when "starred" then @mail_account.messages.starred
      when "trash"   then @mail_account.messages.trashed
      when "drafts"  then @mail_account.messages.drafts
      when "archive"
        archive_folder = @mail_account.archive_folder.presence
        if archive_folder
          @mail_account.messages.not_trashed.not_draft.where(archived: true).or(@mail_account.messages.not_trashed.not_draft.where(folder: archive_folder))
        else
          @mail_account.messages.archived.not_trashed.not_draft
        end
      when "inbox"   then @mail_account.messages.inbox.not_archived
      else                @mail_account.messages.where(folder: @current_folder).not_trashed.not_draft
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
          draft: latest.draft?,
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
        Arel.sql("COUNT(*)"),
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
          @in_reply_to = original.message_id
          @to = original.from_address
          @subject = "Re: #{original.normalized_subject}" unless @subject.present?
          @body = build_reply_body(original) unless @body.present?

          if params[:reply_all]
            all_recipients = original.to_addresses_list + original.cc_addresses_list
            all_recipients -= [ @tool.mail_account.email_address ]
            all_recipients -= [ @to ]
            @cc = all_recipients.join(", ")
          end
        end
      elsif params[:forward].present?
        original = @tool.mail_account.messages.find_by(id: params[:forward])
        if original
          @heading = "Forward"
          @subject = "Fwd: #{original.normalized_subject}" unless @subject.present?
          @body = build_forward_body(original) unless @body.present?
          @forward_attachments = original.attachments.select { |a| a.file.attached? }
        end
      end
    end

    def build_reply_body(message)
      date_str = message.sent_at&.strftime("%a, %b %d, %Y at %I:%M %p")
      quoted = message.body_html.presence || helpers.simple_format(message.body_plain.to_s)
      "<br><br><p>On #{date_str}, #{message.display_from} &lt;#{message.from_address}&gt; wrote:</p><blockquote>#{quoted}</blockquote>"
    end

    def build_forward_body(message)
      forwarded = message.body_html.presence || helpers.simple_format(message.body_plain.to_s)
      "<br><br><p>---------- Forwarded message ----------<br>" \
        "From: #{message.display_from} &lt;#{message.from_address}&gt;<br>" \
        "Date: #{message.sent_at&.strftime('%a, %b %d, %Y at %I:%M %p')}<br>" \
        "Subject: #{ERB::Util.html_escape(message.subject)}<br>" \
        "To: #{ERB::Util.html_escape(message.to_addresses_list.join(', '))}</p>" \
        "#{forwarded}"
    end

    def sync_delete_to_imap(message)
      return unless message.uid.present? && message.folder.present?
      account = @tool.mail_account
      ImapSyncService.new(account).delete_message(message.uid, folder: message.folder)
    end
  end
end
