archived = params[:archived] == "true"

json.tool do
  json.partial! "tools/tool", tool: @tool
end
json.url tool_board_url(@tool)

json.columns @columns do |column|
  json.partial! "tools/boards/columns/column", column: column
  json.cards column.cards.select { |card| card.archived? == archived },
    partial: "tools/boards/cards/card", as: :card, tool: @tool
end
