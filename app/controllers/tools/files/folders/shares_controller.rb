# frozen_string_literal: true

module Tools
  module Files
    module Folders
      class SharesController < ApplicationController
        include ToolAuthorization

        before_action :set_tool
        before_action :set_folder
        before_action -> { authorize_tool_access!(@tool) }

        def show
          @share = @folder.share
          render partial: "tools/files/shares/form", locals: { share: @share, shareable: @folder, share_url: tool_files_folder_share_path(@tool, @folder) }, layout: false
        end

        def create
          @share = @folder.share || @folder.build_share(created_by: Current.user)
          @share.assign_attributes(share_params)

          if @share.save
            render partial: "tools/files/shares/form", locals: { share: @share, shareable: @folder, share_url: tool_files_folder_share_path(@tool, @folder) }, layout: false
          else
            render partial: "tools/files/shares/form", locals: { share: @share, shareable: @folder, share_url: tool_files_folder_share_path(@tool, @folder), errors: @share.errors.full_messages }, status: :unprocessable_entity, layout: false
          end
        end

        def destroy
          @folder.share&.destroy
          redirect_to tool_files_path(@tool, folder_id: @folder.parent_id), notice: "Share removed"
        end

        private

        def set_tool
          @tool = Tool.find(params[:tool_id])
        end

        def set_folder
          @folder = @tool.file_folders.find(params[:folder_id])
        end

        def share_params
          params.permit(:expires_at, :password)
        end
      end
    end
  end
end
