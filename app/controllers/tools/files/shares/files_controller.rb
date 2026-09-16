# frozen_string_literal: true

module Tools
  module Files
    module Shares
      class FilesController < ApplicationController
        include ShareAuthentication

        before_action :require_folder_share

        def show
          @folder = @share.shareable
          @file = @folder.files.find_by(id: params[:id])
          return render_share_not_found unless @file

          @images = @folder.image_files
          @current_index = @images.index(@file)
        end
      end
    end
  end
end
