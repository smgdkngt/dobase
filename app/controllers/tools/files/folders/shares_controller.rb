# frozen_string_literal: true

module Tools
  module Files
    module Folders
      class SharesController < ApplicationController
        include ToolScoped

        # Tokens can see a public link but not create or remove one: a link made
        # with a leaked token would outlive revoking it.
        allow_access_tokens only: :show
        before_action :set_folder
        restrict_in_demo only: :create

        def show
          @share = @folder.share

          respond_to do |format|
            format.html { render partial: "tools/files/shares/form", locals: { share: @share, shareable: @folder, share_url: tool_files_folder_share_path(@tool, @folder) }, layout: false }
            format.json do
              if @share
                render :show
              else
                render json: { error: "This folder has no share link" }, status: :not_found
              end
            end
          end
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
