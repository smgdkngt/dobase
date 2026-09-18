# frozen_string_literal: true

module Tools
  module Todos
    class ListsController < ApplicationController
      include ToolScoped

      allow_access_tokens
      before_action :set_list, only: %i[update destroy]

      def create
        position = @tool.todo_lists.maximum(:position).to_i + 1
        @list = @tool.todo_lists.new(title: params[:title] || "New List", position: position, created_by: current_user, updated_by: current_user)

        respond_to do |format|
          if @list.save
            format.html { redirect_to tool_todo_path(@tool) }
            format.json { render :show, status: :created }
          else
            format.html { redirect_to tool_todo_path(@tool), alert: @list.errors.full_messages.to_sentence }
            format.json { render json: { errors: @list.errors.full_messages }, status: :unprocessable_entity }
          end
        end
      end

      def update
        if @list.update(list_params.merge(updated_by: current_user))
          render :show, formats: :json
        else
          render json: { errors: @list.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @list.destroy!

        respond_to do |format|
          format.html { redirect_to tool_todo_path(@tool) }
          format.json { head :no_content }
        end
      end

      private

      def set_list
        @list = @tool.todo_lists.find(params[:id])
      end

      def list_params
        params.permit(:title, :description)
      end
    end
  end
end
