# frozen_string_literal: true

module Tools
  module Mails
    class ContactsController < ApplicationController
      include ToolScoped

      allow_access_tokens
      before_action :require_mail_account

      # Who an address field offers for what is typed in it: the rows of its list for the
      # compose page, the same people as JSON for the API
      def index
        suggestions = ::Mails::RecipientSuggestions.new(@mail_account).search(params[:q])

        respond_to do |format|
          format.html { render partial: "tools/mails/recipient_suggestions", locals: { suggestions: suggestions, query: params[:q].to_s.strip } }
          format.json { render json: suggestions.map { |suggestion| { email_address: suggestion.address, name: suggestion.name } } }
        end
      end

      private

      def require_mail_account
        @mail_account = @tool.mail_account
        render json: { error: "Mail account not configured" }, status: :not_found unless @mail_account
      end
    end
  end
end
