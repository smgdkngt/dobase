# frozen_string_literal: true

module Tools
  class BoardsController < ApplicationController
    include ToolAuthorization

    allow_access_tokens

    before_action :set_tool
    before_action -> { authorize_tool_access!(@tool) }

    def show
      @board = @tool.board
      @columns = @board.columns.includes(cards: [ :assigned_user, :comments, :attachments, :rich_text_description ]).order(:position)
      @collaborators = @tool.users
      @assignee_filter = params[:assignee]
    end

    private

    def set_tool
      @tool = Tool.find(params[:tool_id])
    end
  end
end
