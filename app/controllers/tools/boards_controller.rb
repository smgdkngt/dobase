# frozen_string_literal: true

module Tools
  class BoardsController < ApplicationController
    include ToolScoped

    allow_access_tokens

    def show
      @board = @tool.board
      @columns = @board.columns.includes(cards: [ :assigned_user, :comments, :attachments, :rich_text_description ]).order(:position)
      @collaborators = @tool.users
      @assignee_filter = params[:assignee]
    end
  end
end
