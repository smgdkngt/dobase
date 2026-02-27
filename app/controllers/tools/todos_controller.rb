# frozen_string_literal: true

module Tools
  class TodosController < ApplicationController
    include ToolAuthorization

    before_action :set_tool
    before_action -> { authorize_tool_access!(@tool) }

    def show
      @lists = @tool.todo_lists.includes(items: [ :assigned_user, :comments, :attachments ]).order(:position)
      @collaborators = @tool.users
    end

    private

    def set_tool
      @tool = Tool.find(params[:tool_id])
    end
  end
end
