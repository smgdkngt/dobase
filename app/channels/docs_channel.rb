# frozen_string_literal: true

class DocsChannel < ApplicationCable::Channel
  def subscribed
    @tool = Tool.find(params[:tool_id])
    reject unless @tool.accessible_by?(current_user)

    stream_for @tool
  end
end
