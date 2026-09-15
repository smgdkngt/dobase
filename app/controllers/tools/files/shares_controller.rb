# frozen_string_literal: true

module Tools
  module Files
    class SharesController < ApplicationController
      include ShareAuthentication

      def show
        if @share.folder?
          @folder = @share.shareable
          @folders = @folder.children.ordered
          @files = @folder.files.ordered
          @images = @folder.image_files
        else
          @file = @share.shareable
        end
      end
    end
  end
end
