# frozen_string_literal: true

module Tools
  class TodosController < ApplicationController
    include ToolScoped

    allow_access_tokens

    def show
      respond_to do |format|
        format.html do
          @lists = @tool.todo_lists.includes(items: [ :assigned_user, :comments, :attachments, :rich_text_description ]).order(:position)
          @collaborators = @tool.users
          @assignee_filter = params[:assignee]
        end
        format.json do
          @lists = @tool.todo_lists.order(:position)
          @items_by_list = listed_items.group_by(&:todo_list_id)
        end
      end
    end

    private

    # What the page shows: open items, then the ones completed in the last day.
    # With completed=true, every completed item instead.
    def listed_items
      items = ::Todos::Item.joins(:list).where(todo_lists: { tool_id: @tool.id })
        .includes(:assigned_user, :comments, :attachments).order(:position)

      params[:completed] == "true" ? items.completed : items.pending + items.recently_completed
    end
  end
end
