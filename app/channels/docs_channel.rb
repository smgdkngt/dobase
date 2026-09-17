# frozen_string_literal: true

class DocsChannel < ApplicationCable::Channel
  def subscribed
    @tool = Tool.find_by(id: params[:tool_id])
    reject and return unless @tool&.accessible_by?(current_user)

    stream_for @tool
  end
end
