# frozen_string_literal: true

module Tools
  module Mails
    class ContactsController < ApplicationController
      include ToolAuthorization

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }
      before_action :require_mail_account

      def index
        query = params[:q].to_s.strip
        results = []

        if query.length >= 2
          # Search saved contacts (people you've emailed)
          contacts = @mail_account.contacts
            .search(query)
            .most_contacted
            .limit(5)
            .select(:email_address, :name)

          results = contacts.map { |c| { email_address: c.email_address, name: c.name } }

          # Also search message senders (people who've emailed you)
          seen = results.map { |r| r[:email_address].downcase }.to_set
          senders = @mail_account.messages
            .where("from_address LIKE :q OR from_name LIKE :q", q: "%#{query}%")
            .where.not(from_address: [ nil, "" ])
            .select(:from_address, :from_name)
            .distinct
            .limit(10)

          senders.each do |msg|
            email = msg.from_address.downcase
            next if seen.include?(email)
            seen.add(email)
            results << { email_address: msg.from_address, name: msg.from_name }
            break if results.size >= 10
          end
        end

        render json: results
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end

      def require_mail_account
        @mail_account = @tool.mail_account
        head :not_found unless @mail_account
      end
    end
  end
end
