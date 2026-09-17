# frozen_string_literal: true

module ToolAuthorization
  extend ActiveSupport::Concern

  # The tool type each namespace under /tools/:tool_id serves
  TOOL_TYPE_SLUGS = {
    "boards" => "boards", "calendars" => "calendar", "chats" => "chat", "docs" => "docs",
    "files" => "files", "mails" => "mail", "rooms" => "room", "todos" => "todos"
  }.freeze

  private

  def authorize_tool_access!(tool)
    ensure_tool_type!(tool)
    unless can_access?(tool)
      deny_tool_access "You don't have access to this tool."
    end
  end

  def authorize_tool_owner!(tool)
    ensure_tool_type!(tool)
    unless can_manage?(tool)
      deny_tool_access "Only the owner can perform this action."
    end
  end

  def can_access?(tool)
    tool.accessible_by?(current_user)
  end

  def can_manage?(tool)
    tool.owned_by?(current_user)
  end

  # A board's id in a mail URL finds no mail, the same as an id that doesn't exist
  def ensure_tool_type!(tool)
    return unless params[:tool_id].present? && tool.id.to_s == params[:tool_id].to_s

    expected = TOOL_TYPE_SLUGS[controller_path.split("/").second]
    raise ActiveRecord::RecordNotFound, "Tool #{tool.id} is not a #{expected} tool" if expected && tool.tool_type.slug != expected
  end

  def deny_tool_access(message)
    if request.format.json?
      render json: { error: message }, status: :forbidden
    else
      redirect_to root_path, alert: message
    end
  end
end
