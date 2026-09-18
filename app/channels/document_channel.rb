# frozen_string_literal: true

# What someone reading a document is told about it while they read: the text as
# it is saved again, and whether anyone has it open in the editor.
#
# The editing itself goes through [DocumentSyncChannel], which is where the
# writers meet.
class DocumentChannel < ApplicationCable::Channel
  def subscribed
    @document = Docs::Document.find_by(id: params[:document_id])
    reject and return unless @document
    reject and return unless @document.tool.accessible_by?(current_user)

    stream_for @document
  end
end
