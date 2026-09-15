# frozen_string_literal: true

module Tools
  module Files
    class FoldersController < ApplicationController
      include ToolAuthorization

      allow_access_tokens
      # API clients send name and parent_id at the top level; the web sends them under folder.
      wrap_parameters :folder, include: %i[name parent_id]

      before_action :set_tool
      before_action -> { authorize_tool_access!(@tool) }
      before_action :set_folder, only: %i[update destroy]

      def create
        parent = params[:parent_id].present? ? @tool.file_folders.find(params[:parent_id]) : nil
        position = (parent&.children || @tool.file_folders.roots).maximum(:position).to_i + 1

        @folder = @tool.file_folders.new(
          name: params[:name].presence || "New Folder",
          parent: parent,
          position: position,
          created_by: current_user,
          updated_by: current_user
        )

        respond_to do |format|
          if @folder.save
            format.html { redirect_to tool_files_path(@tool, folder_id: parent&.id) }
            format.json { render :show, status: :created }
          else
            format.html { redirect_to tool_files_path(@tool, folder_id: parent&.id), alert: @folder.errors.full_messages.to_sentence }
            format.json { render json: { errors: @folder.errors.full_messages }, status: :unprocessable_entity }
          end
        end
      end

      def update
        if @folder.update(folder_params.merge(updated_by: current_user))
          render :show, formats: :json
        else
          render json: { errors: @folder.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        parent_id = @folder.parent_id
        @folder.destroy!

        respond_to do |format|
          format.html { redirect_to tool_files_path(@tool, folder_id: parent_id) }
          format.json { head :no_content }
        end
      end

      private

      def set_tool
        @tool = Tool.find(params[:tool_id])
      end

      def set_folder
        @folder = @tool.file_folders.find(params[:id])
      end

      # A folder can only move into another folder of this tool. A blank parent_id is the top level.
      def folder_params
        params.require(:folder).permit(:name, :parent_id).tap do |permitted|
          permitted[:parent_id] = @tool.file_folders.find(permitted[:parent_id]).id if permitted[:parent_id].present?
        end
      end
    end
  end
end
