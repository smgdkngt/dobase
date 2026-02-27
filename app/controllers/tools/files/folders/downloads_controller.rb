# frozen_string_literal: true

module Tools
  module Files
    module Folders
      class DownloadsController < ApplicationController
        include ToolAuthorization

        before_action :set_tool
        before_action :set_folder
        before_action -> { authorize_tool_access!(@tool) }

        def show
          zip_data = build_folder_zip(@folder)
          send_data zip_data,
                    filename: "#{@folder.name}.zip",
                    type: "application/zip",
                    disposition: "attachment"
        end

        private

        def set_tool
          @tool = Tool.find(params[:tool_id])
        end

        def set_folder
          @folder = @tool.file_folders.find(params[:folder_id])
        end

        def build_folder_zip(folder)
          require "zip"

          stringio = Zip::OutputStream.write_buffer do |zio|
            add_folder_to_zip(zio, folder, "")
          end
          stringio.rewind
          stringio.read
        end

        def add_folder_to_zip(zio, folder, path)
          prefix = path.empty? ? "" : "#{path}/"

          folder.files.each do |file|
            next unless file.file.attached?

            zio.put_next_entry("#{prefix}#{file.name}")
            zio.write(file.file.download)
          end

          folder.children.each do |subfolder|
            add_folder_to_zip(zio, subfolder, "#{prefix}#{subfolder.name}")
          end
        end
      end
    end
  end
end
