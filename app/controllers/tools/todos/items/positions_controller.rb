# frozen_string_literal: true

module Tools
  module Todos
    module Items
      class PositionsController < ApplicationController
        include ToolScoped

        allow_access_tokens
        # A JSON body without "position" would otherwise be wrapped under params[:position].
        wrap_parameters false
        before_action :set_item

        # PATCH /tools/:tool_id/todo/items/:item_id/position
        # Moves an item to todo_list_id (defaults to its own) at position (defaults to the bottom).
        def update
          list = params[:todo_list_id].present? ? @tool.todo_lists.find(params[:todo_list_id]) : @item.list
          @item.move_to(list, position: params[:position], by: current_user)

          respond_to do |format|
            # From the todo's own list picker, inside its dialog: the todo again
            format.html { redirect_to tool_todo_item_path(@tool, @item) }
            format.json { render "tools/todos/items/show" }
          end
        end

        private

        def set_item
          @item = ::Todos::Item.joins(:list).where(todo_lists: { tool_id: @tool.id }).find(params[:item_id])
        end
      end
    end
  end
end
