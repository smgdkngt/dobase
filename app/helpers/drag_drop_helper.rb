# frozen_string_literal: true

# What can be dragged, and where it can be dropped (drag_drop_controller.js, Dropped)
module DragDropHelper
  # The kinds of thing each kind of tool makes something of
  DROPPABLE = {
    "boards" => %w[mail card todo file document message event],
    "todos" => %w[mail card todo file document message event],
    "chat" => %w[mail card todo file document message event],
    "files" => %w[mail card todo file message],
    "mail" => %w[mail card todo file document message event]
  }.freeze

  # An item that can be dragged elsewhere in Dobase, and as a link to any other place.
  # `actions` are its own addresses a place can ask it to go to (a mail's move, archive,
  # trash), for a place that does something to it rather than making something of it.
  # A list that holds less than the record (a mailbox's conversations) gives its title and path.
  def drag_attributes(record, tool: nil, title: nil, path: nil, **actions)
    dropped = Dropped.new(record, tool: tool)
    data = { drag_sgid: Dropped.sgid_for(record), drag_kind: dropped.kind, drag_tool: dropped.tool.id,
             drag_title: title || dropped.title, drag_url: "#{request.base_url}#{path || dropped.path}" }
    actions.each { |action, url| data[:"drag_#{action}_url"] = url }
    { draggable: "true", data: data }
  end

  # A place in a tool that makes something of what is dropped on it: `url` is its
  # create, which takes `dropped`
  def drop_attributes(tool:, url:, done:, accepts: DROPPABLE.fetch(tool.tool_type.slug, []), open: nil)
    { data: { drop_url: url, drop_accepts: accepts.join(" "), drop_tool: tool.id, drop_done: done, drop_open: open }.compact }
  end

  # A place that sends what is dropped on it to one of its own addresses, with `params`
  # (a mail dropped on a folder: its move, to that folder)
  def drop_action_attributes(tool:, action:, done:, params: {})
    { data: { drop_action: action, drop_params: params.to_json, drop_tool: tool.id, drop_done: done } }
  end

  # A tool in the menu, as a place to drop things on (Tools::DropsController)
  def tool_drop_attributes(tool)
    return {} unless DROPPABLE.key?(tool.tool_type.slug)

    drop_attributes(tool: tool, url: tool_drops_path(tool), done: "Added to #{tool.display_name}",
      open: (new_tool_mail_path(tool, draft_id: ":id") if tool.tool_type.slug == "mail"))
  end

  # A mail folder beside the list, as a place to drop a conversation on: what it does
  # to it is what its own button would (a custom folder and the inbox are a move)
  def mail_folder_drop_attributes(folder)
    name = folder[:label]
    case folder[:key]
    when "inbox" then drop_action_attributes(tool: @tool, action: "move", params: { folder: "INBOX" }, done: "Moved to #{name}")
    when "archive" then drop_action_attributes(tool: @tool, action: "archive", done: "Archived")
    when "trash" then drop_action_attributes(tool: @tool, action: "trash", done: "Moved to the trash")
    when "junk" then drop_action_attributes(tool: @tool, action: "junk", done: "Marked as junk")
    when "starred" then drop_action_attributes(tool: @tool, action: "star", done: "Starred")
    when "drafts", "sent" then {}
    else drop_action_attributes(tool: @tool, action: "move", params: { folder: folder[:key] }, done: "Moved to #{name}")
    end
  end
end
