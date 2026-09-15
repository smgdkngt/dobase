# frozen_string_literal: true

module Tools
  module Mails
    class DraftsController < ApplicationController
      include ToolAuthorization

      allow_access_tokens

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }
      before_action :set_mail_account
      before_action :set_draft, only: :update

      # POST /tools/:tool_id/mails/drafts
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
          respond_to do |format|
            format.html { redirect_to new_tool_mail_path(@tool, draft_id: @draft.id), notice: "Draft saved.", status: :see_other }
            format.json { render :show, status: :created }
          end
        else
          respond_to do |format|
            format.html { redirect_to new_tool_mail_path(@tool), alert: "Could not save draft.", status: :see_other }
            format.json { render json: { errors: @draft.errors.full_messages }, status: :unprocessable_entity }
          end
        end
      end

      # PATCH /tools/:tool_id/mails/drafts/:id
      def update
        @draft.assign_attributes(draft_params)
        @draft.sent_at = Time.current

        if @draft.save
          SyncDraftJob.perform_later(@draft.id)
          respond_to do |format|
            format.html { redirect_to new_tool_mail_path(@tool, draft_id: @draft.id), notice: "Draft saved.", status: :see_other }
            format.json { render :show }
          end
        else
          respond_to do |format|
            format.html { redirect_to new_tool_mail_path(@tool, draft_id: @draft.id), alert: "Could not save draft.", status: :see_other }
            format.json { render json: { errors: @draft.errors.full_messages }, status: :unprocessable_entity }
          end
        end
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end

      def set_mail_account
        @mail_account = @tool.mail_account
        return if @mail_account

        respond_to do |format|
          format.html { redirect_to new_tool_mails_account_path(@tool), alert: "Please configure your mail account first." }
          format.json { render json: { error: "Mail account not configured" }, status: :not_found }
        end
      end

      def set_draft
        @draft = @mail_account.messages.drafts.find(params[:id])
      end

      # Only the fields that were sent: the compose form sends all of them, API
      # clients may send just the ones they change.
      def draft_params
        attributes = {}
        attributes[:to_addresses] = address_list(params[:to]).to_json if params.key?(:to)
        attributes[:cc_addresses] = address_list(params[:cc]).presence&.to_json if params.key?(:cc)
        attributes[:subject] = params[:subject] if params.key?(:subject)
        if params.key?(:body)
          attributes[:body_html] = params[:body]
          attributes[:body_plain] = ActionController::Base.helpers.strip_tags(params[:body])&.gsub(/\s+/, " ")&.strip
        end
        attributes[:in_reply_to] = params[:in_reply_to] if params.key?(:in_reply_to)
        attributes
      end

      def address_list(value)
        value.to_s.split(/,\s*/).reject(&:blank?)
      end
    end
  end
end
