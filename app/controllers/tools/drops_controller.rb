# frozen_string_literal: true

module Tools
  # Something dragged onto a tool in the menu (Dropped): sent on, with what was sent
  # here, to the place where that kind of tool makes something of it. A board makes a
  # card in its first column, a todo list a todo in its first list, a chat a message,
  # the files keep the files, mail starts a draft. A 307 keeps the request a POST with
  # its body, so the place it goes to checks and makes it as it always does.
  class DropsController < ApplicationController
    include ToolScoped
    announces_no_change :create

    def create
      if (place = place_for_drops)
        redirect_to place, status: :temporary_redirect
      else
        respond_to do |format|
          format.json { render json: { error: "Nothing can be dropped on #{@tool.name}" }, status: :unprocessable_entity }
          format.any { head :unprocessable_entity }
        end
      end
    end

    private
      def place_for_drops
        case @tool.tool_type.slug
        when "boards" then (column = @tool.board&.columns&.first) && column_cards_path(column)
        when "todos" then (list = @tool.todo_lists.order(:position).first) && todo_list_items_path(list)
        when "chat" then tool_chat_messages_path(@tool)
        when "files" then tool_files_uploads_path(@tool)
        when "mail" then @tool.mail_account && tool_mail_drafts_path(@tool)
        end
      end
  end
end
