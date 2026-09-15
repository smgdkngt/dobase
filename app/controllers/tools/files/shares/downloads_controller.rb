# frozen_string_literal: true

module Tools
  module Files
    module Shares
      class DownloadsController < ApplicationController
        include ShareAuthentication
        include FolderArchiveDownload

        def show
          if @share.folder?
            archive = ::Files::FolderArchive.new(@share.shareable)
            return render(:too_large, status: :content_too_large) if archive.too_large?

            @share.increment_download!
            send_folder_archive archive
          else
            @share.increment_download!
            file = @share.shareable
            send_data file.file.download,
                      filename: file.name,
                      type: file.content_type,
                      disposition: "attachment"
          end
        end
      end
    end
  end
end
