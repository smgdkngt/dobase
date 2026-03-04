module ApplicationHelper
  def app_name = Rails.application.config.x.app.name
  def app_logo_path = Rails.application.config.x.app.logo_path

  TOOL_TYPE_COLORS = {
    "mail" => "#ef4444",     # red
    "calendar" => "#f97316", # orange
    "boards" => "#eab308",   # yellow
    "files" => "#22c55e",    # green
    "docs" => "#3b82f6",     # blue
    "chat" => "#8b5cf6",     # violet
    "todos" => "#ec4899",    # pink
    "room" => "#06b6d4"      # cyan
  }.freeze

  def tool_type_color(tool_type)
    TOOL_TYPE_COLORS[tool_type.slug] || "#6b7280"
  end

  def tool_type_description(tool_type)
    tool_type.description
  end

  def browser_name(user_agent)
    return "Unknown browser" if user_agent.blank?

    case user_agent
    when /Edg\//i then "Microsoft Edge"
    when /Chrome\//i then "Google Chrome"
    when /Firefox\//i then "Mozilla Firefox"
    when /Safari\//i then "Safari"
    when /Opera|OPR\//i then "Opera"
    else "Unknown browser"
    end
  end

  def device_icon(user_agent)
    return "monitor" if user_agent.blank?

    case user_agent
    when /iPhone|Android.*Mobile|Mobile/i then "smartphone"
    when /iPad|Tablet/i then "tablet"
    else "monitor"
    end
  end

  # Returns attribution text like "Created by Alice · Edited by Bob"
  # Only includes names that differ from current_user.
  def attribution_text(record)
    parts = []

    created = record.created_by
    updated = record.updated_by

    if created && created != current_user
      parts << "Created by #{created.name}"
    end

    if updated && updated != current_user && updated != created
      parts << "Edited by #{updated.name}"
    end

    parts.join(" · ").presence
  end
end
