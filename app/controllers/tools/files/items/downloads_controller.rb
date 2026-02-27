# frozen_string_literal: true

module Tools
  module Files
    module Items
      class DownloadsController < ApplicationController
        include ToolAuthorization

        before_action :set_tool
        before_action :set_file
        before_action -> { authorize_tool_access!(@tool) }

        def show
          send_file_download(@file)
        end

        private

        def set_tool
          @tool = Tool.find(params[:tool_id])
        end

        def set_file
          @file = @tool.file_items.find(params[:item_id])
        end

        def send_file_download(file)
          send_data file.file.download,
                    filename: file.name,
                    type: file.content_type,
                    disposition: "attachment"
        end
      end
    end
  end
end
