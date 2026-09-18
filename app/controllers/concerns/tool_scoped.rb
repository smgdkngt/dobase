# frozen_string_literal: true

# Controllers under /tools/:tool_id all work inside one tool: they look it up and check
# that the current user may open it. ToolAuthorization then also checks that the tool is
# the kind this namespace serves.
module ToolScoped
  extend ActiveSupport::Concern

  included do
    include ToolAuthorization

    before_action :set_tool
    before_action -> { authorize_tool_access!(@tool) }
  end

  private

  def set_tool
    @tool = Tool.find(params[:tool_id])
  end
end
