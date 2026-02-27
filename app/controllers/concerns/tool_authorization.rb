# frozen_string_literal: true

module ToolAuthorization
  extend ActiveSupport::Concern

  private

  def authorize_tool_access!(tool)
    unless can_access?(tool)
      redirect_to root_path, alert: "You don't have access to this tool."
    end
  end

  def authorize_tool_owner!(tool)
    unless can_manage?(tool)
      redirect_to root_path, alert: "Only the owner can perform this action."
    end
  end

  def can_access?(tool)
    tool.accessible_by?(current_user)
  end

  def can_manage?(tool)
    tool.owned_by?(current_user)
  end
end
