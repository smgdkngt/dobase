# frozen_string_literal: true

# Who is where across every tool you share, for the faces in the sidebar.
#
# It listens in on each tool's PresenceChannel stream rather than keeping a
# list of its own, so the sidebar hears exactly what the people on a tool's
# page hear. It says nothing about you: you are in a tool when you have its
# page open, not because your sidebar is showing it.
class WorkspacePresenceChannel < ApplicationCable::Channel
  def subscribed
    @tools = current_user.accessible_tools.to_a
    @tools.each { |tool| stream_from PresenceChannel.broadcasting_for(tool) }
  end

  # A sidebar that just arrived asks everyone on each tool to say where they
  # are, instead of waiting up to half a minute for their next heartbeat.
  # Action Cable only hands over the payload to a one-argument action.
  def roll_call(_data)
    @tools&.each do |tool|
      ActionCable.server.broadcast(PresenceChannel.broadcasting_for(tool), { type: "roll_call", tool_id: tool.id })
    end
  end
end
