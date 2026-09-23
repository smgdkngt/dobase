# frozen_string_literal: true

module Tools
  module Files
    module Items
      class SharesController < ApplicationController
        include ToolScoped

        # Tokens can see a public link but not create or remove one: a link made
        # with a leaked token would outlive revoking it.
        allow_access_tokens only: :show
        before_action :set_file
        restrict_in_demo only: :create

        def show
          @share = @file.share

          respond_to do |format|
            format.html { render partial: "tools/files/shares/form", locals: { share: @share, shareable: @file, share_url: tool_files_item_share_path(@tool, @file) }, layout: false }
            format.json do
              if @share
                render :show
              else
                render json: { error: "This file has no share link" }, status: :not_found
              end
            end
          end
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
