# frozen_string_literal: true

module Tools
  # A file of a mail, a card, a todo or a chat, downloaded. Like its preview
  # (FilePreviewsController) it is named by its attachment and only given when what it
  # is attached to lies in this tool, which ToolScoped has checked the person may open:
  # this is the address the download arrow and the API hand out, so a link that is
  # copied, pasted into a chat or kept in an agent's transcript is worth nothing to
  # whoever isn't in the tool. The file itself comes from a storage link that lasts
  # five minutes.
  class FileDownloadsController < ApplicationController
    include ToolScoped

    allow_access_tokens

    def show
      attachment = ActiveStorage::Attachment.includes(:blob).find(params[:id])
      raise ActiveRecord::RecordNotFound, "File #{attachment.id} is not in this tool" unless FileOfATool.tool_of(attachment.record) == @tool

      redirect_to rails_blob_path(attachment.blob, disposition: "attachment", expires_in: 5.minutes), allow_other_host: false
    end
  end
end
