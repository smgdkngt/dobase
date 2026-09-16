# frozen_string_literal: true

module Tools
  module Files
    module Shares
      module Files
        # One file from a shared folder, where the share's own download is the whole folder as a zip.
        class DownloadsController < ApplicationController
          include ShareAuthentication
          include FileItemDownload

          before_action :require_folder_share

          def show
            file = @share.shareable.files.find_by(id: params[:file_id])
            return render_share_not_found unless file

            @share.increment_download!
            send_file_item file
          end
        end
      end
    end
  end
end
