# frozen_string_literal: true

module Tools
  class DocsController < ApplicationController
    include ToolAuthorization

    before_action :set_tool
    before_action -> { authorize_tool_access!(@tool) }

    def show
      @documents = @tool.documents.includes(:last_edited_by, :locked_by).ordered
      @view_mode = params[:view].presence_in(%w[grid list]) || cookies[:docs_view] || "grid"

      if params[:view].present? && params[:view] != cookies[:docs_view]
        cookies[:docs_view] = { value: params[:view], expires: 1.year.from_now }
      end
    end

    private

    def set_tool
      @tool = Tool.find(params[:tool_id])
    end
  end
end
