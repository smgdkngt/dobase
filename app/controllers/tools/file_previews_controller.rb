# frozen_string_literal: true

module Tools
  # A file shown in the app instead of downloaded: an attachment of a mail (a draft's
  # too), a card or a todo, a file in a chat or in the Files tool. One page for all of
  # them, opened as a dialog over the page it was asked from (file_viewer_controller.js).
  #
  # The file is named by its attachment (Active Storage's own record of what a file is
  # attached to) and is only shown when what it is attached to lies in this tool, which
  # ToolScoped has checked the person may open.
  class FilePreviewsController < ApplicationController
    include ToolScoped

    allow_access_tokens

    def show
      attachment = ActiveStorage::Attachment.includes(:blob).find(params[:id])
      raise ActiveRecord::RecordNotFound, "File #{attachment.id} is not in this tool" unless FileOfATool.tool_of(attachment.record) == @tool

      @attachment = attachment
      @preview = FilePreview.new(attachment.blob, name: (attachment.record.name if attachment.record.is_a?(::Files::Item)))
    end
  end
end
