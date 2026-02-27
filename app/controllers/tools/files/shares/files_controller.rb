# frozen_string_literal: true

module Tools
  module Files
    module Shares
      class FilesController < ApplicationController
        include ShareAuthentication

        def show
          @folder = @share.shareable
          @file = @folder.files.find(params[:id])
          @images = @folder.image_files
          @current_index = @images.index(@file)
        end
      end
    end
  end
end
