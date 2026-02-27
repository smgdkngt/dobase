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

      private

      def set_share
        @share = ::Files::Share.find_by!(token: params[:token])
      rescue ActiveRecord::RecordNotFound
        render :not_found, status: :not_found
      end
    end
  end
end
