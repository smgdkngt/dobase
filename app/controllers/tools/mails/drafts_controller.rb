# frozen_string_literal: true

module Tools
  module Mails
    class DraftsController < ApplicationController
      include ToolAuthorization

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }
      before_action :set_mail_account
      before_action :set_draft, only: :update

      # POST /tools/:tool_id/mails/draft
      def create
        @draft = @mail_account.messages.new(draft_params)
        @draft.draft = true
        @draft.message_id = "<draft-#{SecureRandom.uuid}@local>"
        @draft.folder = "Drafts"
        @draft.from_address = @mail_account.email_address
        @draft.from_name = @mail_account.display_name
        @draft.read = true
        @draft.sent_at = Time.current

        if @draft.save
          SyncDraftJob.perform_later(@draft.id)
          redirect_to new_tool_mail_path(@tool, draft_id: @draft.id), notice: "Draft saved.", status: :see_other
        else
          redirect_to new_tool_mail_path(@tool), alert: "Could not save draft.", status: :see_other
        end
      end

      # PATCH /tools/:tool_id/mails/draft
      def update
        @draft.assign_attributes(draft_params)
        @draft.sent_at = Time.current

        if @draft.save
          SyncDraftJob.perform_later(@draft.id)
          redirect_to new_tool_mail_path(@tool, draft_id: @draft.id), notice: "Draft saved.", status: :see_other
        else
          redirect_to new_tool_mail_path(@tool, draft_id: @draft.id), alert: "Could not save draft.", status: :see_other
        end
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end

      def set_mail_account
        @mail_account = @tool.mail_account
        redirect_to new_tool_mails_account_path(@tool), alert: "Please configure your mail account first." unless @mail_account
      end

      def set_draft
        @draft = @mail_account.messages.drafts.find(params[:id])
      end

      def draft_params
        to = params[:to].to_s.split(/,\s*/).reject(&:blank?)
        cc = params[:cc].to_s.split(/,\s*/).reject(&:blank?)
        body_html = params[:body]
        body_plain = ActionController::Base.helpers.strip_tags(body_html)&.gsub(/\s+/, " ")&.strip

        {
          to_addresses: to.to_json,
          cc_addresses: cc.presence&.to_json,
          subject: params[:subject],
          body_html: body_html,
          body_plain: body_plain,
          in_reply_to: params[:in_reply_to]
        }
      end
    end
  end
end
