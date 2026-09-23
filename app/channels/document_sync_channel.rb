# frozen_string_literal: true

# Everyone writing in the same document at the same time.
#
# The browsers keep the text in a Yjs document, which merges concurrent edits
# on its own. Dobase is the post office and the filing cabinet: it hands a
# joining page every change made so far, passes on each new one, and keeps them.
# Cursors travel the same way but are never kept — where someone's caret is
# stops being true the moment they move it.
#
# Only a browser can merge those changes into one, so when the pile grows the
# newest arrival is asked to send a merged copy back, which replaces it.
class DocumentSyncChannel < ApplicationCable::Channel
  # Past this many stored changes, ask for a merged copy
  COMPACT_AFTER = 200
  # A change this big is no longer typing: whole books are a few MB of text.
  # The limits keep one page from filling the database.
  MAX_UPDATE_SIZE = 5.megabytes
  MAX_DOCUMENT_SIZE = 50.megabytes
  MAX_CARET_SIZE = 64.kilobytes

  def subscribed
    document = Docs::Document.find_by(id: params[:document_id])
    reject and return unless document&.tool&.accessible_by?(current_user)

    @document = document
    stream_for @document
    DocumentPresence.connect(@document.id, current_user.id)
    hold_editing_open

    transmit({
      type: "sync",
      updates: stored_updates,
      seed: seed_html,
      compact: @document.updates.count > COMPACT_AFTER
    })
  end

  def unsubscribed
    return unless @document
    return unless DocumentPresence.disconnect(@document.id, current_user.id)

    release_editing
  end

  # A change someone made, on its way to everyone else and to the filing cabinet
  def apply_update(data)
    return unless @document

    # Measured before decoding, so a huge one is never decoded at all
    return refuse("This change is too large to share") if data["update"].to_s.bytesize > encoded_size(MAX_UPDATE_SIZE)

    payload = decode(data["update"])
    # Not blank?: these are bytes, and a change that happens to be whitespace
    # is still a change
    return if payload.nil? || payload.empty?
    return refuse("This document is too large to share more changes") if stored_size + payload.bytesize > MAX_DOCUMENT_SIZE

    @document.updates.create!(data: payload)
    hold_editing_open
    broadcast(type: "update", update: data["update"], origin: data["origin"])
  end

  # Where someone's caret is. Passed on, never kept. A page that just arrived
  # says hello with it, and everyone else answers with theirs.
  def move_caret(data)
    return unless @document
    return if data["awareness"].to_s.empty? || data["awareness"].to_s.bytesize > MAX_CARET_SIZE

    broadcast(type: "awareness", awareness: data["awareness"], origin: data["origin"], hello: data["hello"].present?)
  end

  # The pile, merged into one by a browser that had the whole document
  def merge_updates(data)
    return unless @document

    return if data["snapshot"].to_s.bytesize > encoded_size(MAX_DOCUMENT_SIZE)

    payload = decode(data["snapshot"])
    return if payload.nil? || payload.empty?

    Docs::Update.transaction do
      @document.updates.delete_all
      @document.updates.create!(data: payload, seed: true)
    end
  end

  private

  def broadcast(payload)
    DocumentSyncChannel.broadcast_to(@document, payload)
  end

  # The row that claims the first fill holds no change of its own, and Yjs
  # refuses to read an empty one
  def stored_updates
    @document.updates.oldest_first.pluck(:data)
      .reject { |data| data.nil? || data.empty? }
      .map { |data| Base64.strict_encode64(data) }
  end

  # The text as it stands goes to the first page to open the document, which
  # builds the shared copy from it. The row claiming that is written here, so
  # two pages arriving together can't both fill the same document.
  def seed_html
    return nil if @document.updates.exists?

    @document.updates.create!(data: "", seed: true)
    @document.content&.body&.to_html.to_s
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def decode(value)
    Base64.strict_decode64(value.to_s)
  rescue ArgumentError
    nil
  end

  # Changes arrive as Base64, a third longer than the bytes it carries
  def encoded_size(bytes)
    (bytes + 2) / 3 * 4
  end

  def stored_size
    @document.updates.sum("length(data)")
  end

  # Only the page that sent it hears; the others never got the change
  def refuse(reason)
    transmit({ type: "refused", reason: reason })
  end

  # The documents list and the API ask whether anyone has this open. Taking it
  # doesn't keep anyone else out — it's a sign, not a lock.
  def hold_editing_open
    taken = Docs::Document.where(id: @document.id)
      .where("locked_by_id IS NULL OR locked_at < ? OR locked_by_id = ?", Docs::Document::LOCK_TIMEOUT.ago, current_user.id)
      .update_all(locked_by_id: current_user.id, locked_at: Time.current)

    announce_editing(current_user.name) if taken.positive? && !@holding
    @holding = true if taken.positive?
  end

  def release_editing
    return unless @holding

    released = Docs::Document.where(id: @document.id, locked_by_id: current_user.id)
      .update_all(locked_by_id: nil, locked_at: nil)

    announce_editing(nil) if released.positive?
  end

  # Two audiences: whoever is reading this document (DocumentChannel) and the
  # documents list, where a card says who is writing (DocsChannel).
  def announce_editing(user_name)
    payload = { type: user_name ? "locked" : "unlocked", user_name: user_name }.compact

    DocumentChannel.broadcast_to(@document, payload)
    DocsChannel.broadcast_to(@document.tool, payload.merge(document_id: @document.id))
  end
end
