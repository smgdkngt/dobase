# frozen_string_literal: true

module Tools
  module Files
    module Shares
      class DownloadsController < ApplicationController
        include ShareAuthentication
        include FolderArchiveDownload
        include FileItemDownload

        def show
          if @share.folder?
            archive = ::Files::FolderArchive.new(@share.shareable)
            return render(:too_large, status: :content_too_large) if archive.too_large?

            @share.increment_download!
            send_folder_archive archive
          else
            @share.increment_download!
            send_file_item @share.shareable
          end
        end
      end
    end
  end
end
