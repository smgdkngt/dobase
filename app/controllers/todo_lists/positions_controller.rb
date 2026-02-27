# frozen_string_literal: true

module TodoLists
  class PositionsController < ApplicationController
    include ToolAuthorization

    before_action :set_list
    before_action :set_tool
    before_action -> { authorize_tool_access!(@tool) }

    def update
      params[:item_ids].each_with_index do |id, index|
        ::Todos::Item.where(id: id).update_all(todo_list_id: @list.id, position: index)
      end
      render json: { success: true }
    end

    private

    def set_list
      @list = ::Todos::List.find(params[:todo_list_id])
    end

    def set_tool
      @tool = @list.tool
    end
  end
end
