# frozen_string_literal: true

module TodoLists
  class ItemsController < ApplicationController
    include ToolAuthorization

    allow_access_tokens

    before_action :set_list
    before_action :set_tool
    before_action -> { authorize_tool_access!(@tool) }

    def create
      position = @list.items.maximum(:position).to_i + 1
      @item = @list.items.new(item_params.merge(position: position, created_by: current_user, updated_by: current_user))

      respond_to do |format|
        if @item.save
          @item.notify_assignee(current_user)
          format.html { redirect_to tool_todo_path(@tool) }
          format.json { render "tools/todos/items/show", status: :created }
        else
          format.html { redirect_to tool_todo_path(@tool), alert: @item.errors.full_messages.to_sentence }
          format.json { render json: { errors: @item.errors.full_messages }, status: :unprocessable_entity }
        end
      end
    end

    private

    def set_list
      @list = ::Todos::List.find(params[:todo_list_id])
    end

    def set_tool
      @tool = @list.tool
    end

    def item_params
      params.require(:item).permit(:title, :description, :due_date, :assigned_user_id, :recurrence_rule)
    end
  end
end
