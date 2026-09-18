# frozen_string_literal: true

module TodoLists
  class PositionsController < ApplicationController
    include ToolAuthorization

    before_action :set_list
    before_action :set_tool
    before_action -> { authorize_tool_access!(@tool) }

    def update
      # Only the items the request lists move to this list. One that isn't listed was hidden
      # by a filter, or has just been dragged to another list while this request was on its
      # way: claiming it back would drag it out of the list it went to.
      item_ids = tool_item_ids
      list_order(item_ids).each_with_index do |id, index|
        changes = { position: index }
        changes[:todo_list_id] = @list.id if item_ids.include?(id)
        ::Todos::Item.where(id: id).update_all(changes)
      end
      render json: { success: true }
    end

    private

    def set_list
      @list = ::Todos::List.find(params[:todo_list_id])
    end

    def set_tool
      @tool = @list.tool
    end

    # With the assignee filter on, the request only lists the items that were shown.
    # The list's other items keep their places: each stays after the item it followed.
    def list_order(requested)
      KeepHiddenInPlace.call(@list.items.order(:position, :id).ids, requested)
    end

    # The requested item ids, in order, limited to items in this tool's lists.
    # Ids of items from other tools are dropped rather than moved over.
    def tool_item_ids
      requested = Array(params[:item_ids]).map(&:to_i)
      requested & ::Todos::Item.joins(:list).where(todo_lists: { tool_id: @tool.id }, id: requested).ids
    end
  end
end
