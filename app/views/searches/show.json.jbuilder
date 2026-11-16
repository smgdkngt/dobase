# frozen_string_literal: true

json.query @search.query
json.kind @search.kind
json.totals @search.totals
json.results @search.hits do |hit|
  json.kind hit.kind
  json.title hit.title
  json.excerpt hit.excerpt
  json.date hit.date&.iso8601
  json.archived hit.archived
  json.tool_id hit.tool&.id
  json.tool_name hit.tool&.display_name
  json.url absolute_url(hit.path)
end
