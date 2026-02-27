# frozen_string_literal: true

module Tools
  module Files
    module Shares
      class DownloadsController < ApplicationController
        include ShareAuthentication

        def show
          @share.increment_download!

          if @share.folder?
            folder = @share.shareable
            zip_data = build_folder_zip(folder)
            send_data zip_data,
                      filename: "#{folder.name}.zip",
                      type: "application/zip",
                      disposition: "attachment"
          else
            file = @share.shareable
            send_data file.file.download,
                      filename: file.name,
                      type: file.content_type,
                      disposition: "attachment"
          end
        end

        private

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
