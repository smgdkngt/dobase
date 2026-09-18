# frozen_string_literal: true

module Tools
  module Files
    module Items
      class DownloadsController < ApplicationController
        include ToolScoped
        include FileItemDownload

        allow_access_tokens
        before_action :set_file

        def show
          send_file_item(@file)
        end

        private

        def set_file
          @file = @tool.file_items.find(params[:item_id])
        end
      end
    end
  end
end
