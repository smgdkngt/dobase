# frozen_string_literal: true

class DocumentChannel < ApplicationCable::Channel
  def subscribed
    @document = Docs::Document.find_by(id: params[:document_id])
    reject and return unless @document
    reject and return unless @document.tool.accessible_by?(current_user)

    stream_for @document
  end

  def unsubscribed
    return unless @document

    # Atomically release only our lock
    rows_updated = Docs::Document
      .where(id: @document.id, locked_by_id: current_user.id)
      .update_all(locked_by_id: nil, locked_at: nil)

    if rows_updated > 0
      DocumentChannel.broadcast_to(@document, { type: "unlocked", user_name: current_user.name })
      DocsChannel.broadcast_to(@document.tool, {
        type: "unlocked",
        document_id: @document.id
      })
    end
  end

  def refresh_lock
    return unless @document

    # Atomic update: only refresh if we still hold the lock
    Docs::Document
      .where(id: @document.id, locked_by_id: current_user.id)
      .update_all(locked_at: Time.current)
  end

  def start_editing
    return unless @document

    # Atomic lock acquisition: only if not locked by someone else
    rows_updated = Docs::Document.where(id: @document.id)
      .where(
        "locked_by_id IS NULL OR locked_at < ? OR locked_by_id = ?",
        Docs::Document::LOCK_TIMEOUT.ago,
        current_user.id
      )
      .update_all(locked_by_id: current_user.id, locked_at: Time.current)

    if rows_updated > 0
      DocumentChannel.broadcast_to(@document, {
        type: "locked",
        user_name: current_user.name
      })
      DocsChannel.broadcast_to(@document.tool, {
        type: "locked",
        document_id: @document.id,
        user_name: current_user.name
      })
    else
      # Lock rejected - someone else has it
      @document.reload
      transmit({ type: "lock_rejected", locked_by: @document.locked_by&.name })
    end
  end
end
