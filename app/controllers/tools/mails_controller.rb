# frozen_string_literal: true

module Tools
  class MailsController < ApplicationController
    include ToolAuthorization

    before_action :set_tool
    before_action -> { authorize_tool_access!(@tool) }
    before_action :require_mail_account, except: [ :index ]
    before_action :set_message, only: [ :show, :destroy ]
    before_action :build_compose_defaults, only: [ :new ]

    PER_PAGE = 30

    def index
      if @tool.mail_account.nil?
        redirect_to new_tool_mails_account_path(@tool) and return if @tool.owned_by?(current_user)
        redirect_to tool_path(@tool), alert: "Mail account not configured." and return
      end

      @mail_account = @tool.mail_account
      @current_folder = params[:folder] || "inbox"
      @inbox_unread = @mail_account.messages.inbox.not_archived.unread.count
      @trash_count = @mail_account.messages.trashed.count
      @custom_folders = @mail_account.custom_folders

      base_scope = case @current_folder
      when "sent"    then @mail_account.messages.sent
      when "starred" then @mail_account.messages.starred
      when "trash"   then @mail_account.messages.trashed
      when "archive" then @mail_account.messages.archived.not_trashed
      when "inbox"   then @mail_account.messages.inbox.not_archived
      else                @mail_account.messages.where(folder: @current_folder).not_trashed
      end

      base_scope = base_scope.search(params[:q]) if params[:q].present?
      @conversations = fetch_conversations(base_scope)

      if params[:selected].present?
        @selected_message = @mail_account.messages.find_by(id: params[:selected])
        if @selected_message
          @conversation_messages = @selected_message.conversation.to_a
          @selected_message.conversation.unread.find_each(&:mark_as_read!)
        end
      end

      respond_to do |format|
        format.html
        format.turbo_stream
      end
    end

    def show
      @mail_account = @tool.mail_account
      @conversation_messages = @message.conversation.to_a
      @message.conversation.unread.find_each(&:mark_as_read!)

      respond_to do |format|
        format.html { redirect_to tool_mails_path(@tool, selected: @message.id) }
        format.turbo_stream
      end
    end

    def new
      @mail_account = @tool.mail_account
    end

    def create
      @mail_account = @tool.mail_account

      to = params[:to].to_s.split(/,\s*/).reject(&:blank?)
      cc = params[:cc].presence&.split(/,\s*/)&.reject(&:blank?)
      bcc = params[:bcc].presence&.split(/,\s*/)&.reject(&:blank?)

      all_addresses = [ *to, *cc, *bcc ]
      invalid = all_addresses.reject { |a| a.match?(URI::MailTo::EMAIL_REGEXP) }

      if invalid.any?
        flash.now[:alert] = "Invalid email address: #{invalid.first}"
        build_compose_defaults
        render :new, status: :unprocessable_entity
        return
      end

      body_html = params[:body]
      body_plain = ActionController::Base.helpers.strip_tags(body_html)&.gsub(/\s+/, " ")&.strip

      service = SmtpSendService.new(@mail_account)
      service.send_email(
        to: to,
        cc: cc,
        bcc: bcc,
        subject: params[:subject],
        body: body_plain,
        body_html: body_html,
        attachments: params[:attachments]
      )

      redirect_to tool_mails_path(@tool, folder: "sent"), notice: "Email sent successfully."
    rescue SmtpSendService::SendError => e
      flash.now[:alert] = e.message
      build_compose_defaults
      render :new, status: :unprocessable_entity
    end

    def destroy
      if @message.trashed?
        @message.destroy
        redirect_to tool_mails_path(@tool, folder: "trash"), notice: "Email permanently deleted."
      else
        @message.update(trashed: true)
        redirect_to tool_mails_path(@tool), notice: "Email moved to trash."
      end
    end

    private

    def set_tool
      @tool = Tool.find(params[:tool_id])
    end

    def require_mail_account
      unless @tool.mail_account
        redirect_to new_tool_mails_account_path(@tool), alert: "Please configure your mail account first."
      end
    end

    def set_message
      @mail_account = @tool.mail_account
      @message = @mail_account.messages.find(params[:id])
    end

    def fetch_conversations(scope)
      thread_ids = scope.select(:thread_id).distinct.pluck(:thread_id)

      conversations = thread_ids.filter_map do |thread_id|
        thread_messages = scope.where(thread_id: thread_id).order(sent_at: :desc)
        latest = thread_messages.first
        next unless latest

        {
          id: latest.id,
          thread_id: thread_id,
          subject: latest.normalized_subject.presence || "(No subject)",
          from: latest.display_from,
          from_address: latest.from_address,
          preview: latest.preview,
          sent_at: latest.sent_at,
          read: thread_messages.unread.none?,
          starred: thread_messages.starred.any?,
          has_attachments: thread_messages.with_attachments.any?,
          count: thread_messages.count,
          unread_count: thread_messages.unread.count,
          participants: thread_messages.pluck(:from_name, :from_address).uniq.map { |n, a| n.presence || a }.first(3)
        }
      end

      @page = (params[:page] || 1).to_i
      conversations = conversations.sort_by { |c| c[:sent_at] || Time.at(0) }.reverse

      @total_count = conversations.size
      @total_pages = (@total_count / PER_PAGE.to_f).ceil
      @page = [ [ @page, 1 ].max, [ @total_pages, 1 ].max ].min

      conversations.slice((@page - 1) * PER_PAGE, PER_PAGE) || []
    end

    def build_compose_defaults
      @to = params[:to] || ""
      @cc = params[:cc] || ""
      @bcc = params[:bcc] || ""
      @subject = params[:subject] || ""
      @body = params[:body] || ""

      if params[:reply_to].present?
        original = @tool.mail_account.messages.find_by(id: params[:reply_to])
        if original
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
          @subject = "Fwd: #{original.normalized_subject}" unless @subject.present?
          @body = build_forward_body(original) unless @body.present?
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
  end
end
