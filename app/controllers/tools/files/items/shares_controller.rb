# frozen_string_literal: true

module Tools
  module Files
    module Items
      class SharesController < ApplicationController
        include ToolAuthorization

        before_action :set_tool
        before_action :set_file
        before_action -> { authorize_tool_access!(@tool) }

        def show
          @share = @file.share
          render partial: "tools/files/shares/form", locals: { share: @share, shareable: @file, share_url: tool_files_item_share_path(@tool, @file) }, layout: false
        end

        def create
          @share = @file.share || @file.build_share(created_by: Current.user)
          @share.assign_attributes(share_params)

          if @share.save
            render partial: "tools/files/shares/form", locals: { share: @share, shareable: @file, share_url: tool_files_item_share_path(@tool, @file) }, layout: false
          else
            render partial: "tools/files/shares/form", locals: { share: @share, shareable: @file, share_url: tool_files_item_share_path(@tool, @file), errors: @share.errors.full_messages }, layout: false
          end
        end

        def destroy
          @file.share&.destroy
          redirect_to tool_files_item_path(@tool, @file), notice: "Share removed"
        end

        private

        def set_tool
          @tool = Tool.find(params[:tool_id])
        end

        def set_file
          @file = @tool.file_items.find(params[:item_id])
        end

        def share_params
          params.permit(:expires_at, :password)
        end
      end
    end
  end
end
