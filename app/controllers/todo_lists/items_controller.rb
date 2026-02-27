# frozen_string_literal: true

module TodoLists
  class ItemsController < ApplicationController
    include ToolAuthorization

    before_action :set_list
    before_action :set_tool
    before_action -> { authorize_tool_access!(@tool) }

    def create
      position = @list.items.maximum(:position).to_i + 1
      @list.items.create!(title: params[:title], position: position)
      redirect_to tool_todo_path(@tool)
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
