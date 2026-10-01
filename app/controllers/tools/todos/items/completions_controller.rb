# frozen_string_literal: true

module Tools
  module Todos
    module Items
      class CompletionsController < ApplicationController
        include ToolScoped

        allow_access_tokens
        before_action :set_item

        # POST /tools/:tool_id/todo/items/:item_id/completion
        # Completing an item twice changes nothing, so a retry can't spawn a
        # second copy of a recurring item, or notify its assignee again.
        def create
          notify_completion if @item.complete!(by: current_user)
          respond_with_item
        end

        # DELETE /tools/:tool_id/todo/items/:item_id/completion
        # Putting a repeating item back on the list takes its copy with it,
        # unless someone has started on that copy.
        def destroy
          ::Todos::Item.transaction do
            @item.discard_untouched_copy!
            @item.update!(completed_at: nil, updated_by: current_user)
          end
          respond_with_item
        end

        private

        def set_item
          @item = ::Todos::Item.joins(:list).where(todo_lists: { tool_id: @tool.id }).find(params[:item_id])
        end

        def respond_with_item
          respond_to do |format|
            format.html { redirect_to tool_todo_path(@tool) }
            format.json { render "tools/todos/items/show" }
          end
        end

        def notify_completion
          assignee = @item.assigned_user
          return if assignee.nil? || assignee == current_user
          return if @tool.muted_by?(assignee) || !@tool.accessible_by?(assignee)

          TodoCompletedNotifier.with(item: @item, completer: current_user, tool: @tool).deliver(assignee)
          assignee.prune_notifications!
        end
      end
    end
  end
end
