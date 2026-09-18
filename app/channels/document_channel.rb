# frozen_string_literal: true

class DocumentChannel < ApplicationCable::Channel
  def subscribed
    @document = Docs::Document.find_by(id: params[:document_id])
    reject and return unless @document
    reject and return unless @document.tool.accessible_by?(current_user)

    stream_for @document
  end

  # Only the connection that took the lock gives it back. A read-only viewer of
  # the same document, or another tab of the same user, must not release the lock
  # the editor is holding.
  def unsubscribed
    return unless @document && @editing

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

  # Keeps our lock fresh, and takes it back if it lapsed or someone released it
  # meanwhile. Only the editor calls this, so this connection is an editing one.
  def refresh_lock
    return unless @document

    kept = Docs::Document
      .where(id: @document.id, locked_by_id: current_user.id)
      .update_all(locked_at: Time.current)

    if kept.zero?
      start_editing
    else
      @editing = true
    end
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
      @editing = true
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
