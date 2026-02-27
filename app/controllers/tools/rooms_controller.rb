# frozen_string_literal: true

module Tools
  class RoomsController < ApplicationController
    include ToolAuthorization

    before_action :set_tool
    before_action -> { authorize_tool_access!(@tool) }

    def show
      @room = @tool.room
    end

    private

    def set_tool
      @tool = Tool.find(params[:tool_id])
    end
  end
end
