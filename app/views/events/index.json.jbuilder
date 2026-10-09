# frozen_string_literal: true

json.events @events do |event|
  tool = @tools[event.tool_id]

  json.id event.id
  json.kind event.kind
  json.at event.created_at.utc.iso8601
  json.tool do
    json.id event.tool_id
    # Names are somebody's text too: one line, like what an event carries
    json.name tool && Event.line(tool.name)
    json.type tool&.tool_type&.slug
  end
  # How the CLI names the thing: `dobase card show 110/44`
  json.ref event.record_id && "#{event.tool_id}/#{event.record_id}"
  # Who did it: nobody when it came from outside (mail that arrived, a sync)
  if event.user_id
    json.by do
      json.id event.user_id
      json.name event.user && Event.line(event.user.name)
      json.via event.via && Event.line(event.via)
      json.agent event.agent
    end
  else
    json.by nil
  end
  json.own event.made_with?(Current.access_token)
  json.data event.data
end
json.cursor @cursor
json.more @more
json.gap @gap
