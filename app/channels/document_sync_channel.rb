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
#
# The pile is one copy of the text, and a page writes in the copy it joined.
# When that copy is thrown away (Docs::Document#reset_shared_copy!) the page's
# changes fit nowhere any more: they are refused, and the page starts over.
class DocumentSyncChannel < ApplicationCable::Channel
  # Past this many stored changes, ask for a merged copy
  COMPACT_AFTER = 200
  # Carets move with every keystroke; that the document is open is written down
  # this often at most. Well inside Docs::Document::LOCK_TIMEOUT.
  HOLD_EVERY = 30.seconds
  # A change this big is no longer typing: whole books are a few MB of text.
  # The limits keep one page from filling the database.
  MAX_UPDATE_SIZE = 5.megabytes
  MAX_DOCUMENT_SIZE = 50.megabytes
  MAX_CARET_SIZE = 64.kilobytes
  # People leave one at a time, so that who is left is still there when the
  # "is editing" sign is passed on to them
  LEAVING = Mutex.new

  def subscribed
    document = Docs::Document.find_by(id: params[:document_id])
    reject and return unless document&.tool&.accessible_by?(current_user)

    @document = document
    stream_for @document
    DocumentPresence.connect(@document.id, current_user.id)
    hold_editing_open

    transmit(copy_to_join)
  end

  def unsubscribed
    return unless @document

    give_up_seeding
    LEAVING.synchronize do
      release_editing if DocumentPresence.disconnect(@document.id, current_user.id)
    end
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
    return refuse("The demo is full right now") if Demo.over_budget?

    return start_over unless in_this_copy { @document.updates.create!(data: payload) }

    keep_editing_open
    broadcast(type: "update", update: data["update"], origin: data["origin"])
  end

  # Where someone's caret is. Passed on, never kept. A page that just arrived
  # says hello with it, and everyone else answers with theirs.
  def move_caret(data)
    return unless @document
    return if data["awareness"].to_s.empty? || data["awareness"].to_s.bytesize > MAX_CARET_SIZE

    keep_editing_open
    broadcast(type: "awareness", awareness: data["awareness"], origin: data["origin"], hello: data["hello"].present?)
  end

  # Someone reading along, or thinking, types nothing and moves no caret, and
  # still has the document open. Their page says so every minute.
  def still_here
    keep_editing_open if @document
  end

  # The pile, merged into one by a browser that had the whole document — as far
  # as it had read. It says how far, and only that much is replaced: a change
  # that came in while it was merging is not in its copy, and stays.
  def merge_updates(data)
    return unless @document

    return if data["snapshot"].to_s.bytesize > encoded_size(MAX_DOCUMENT_SIZE)

    payload = decode(data["snapshot"])
    return if payload.nil? || payload.empty?

    upto = data["upto"].to_i
    return unless upto.positive?

    merged = in_this_copy do
      # Another page sent its merged copy in the meantime, and that one has more in it
      next if @document.updates.where(seed: true).where("id > ?", upto).exists?

      @document.updates.where(id: ..upto).delete_all
      @document.updates.create!(data: payload, seed: true)
    end

    start_over unless merged
  end

  private

  def broadcast(payload)
    DocumentSyncChannel.broadcast_to(@document, payload)
  end

  # What a joining page is handed: which copy this is, every change in it, and
  # the text to build it from if nobody has yet. Read in one transaction, so the
  # copy can't be thrown away halfway and leave the page with a bit of each.
  def copy_to_join
    Docs::Update.transaction do
      @generation = Docs::Document.where(id: @document.id).pick(:shared_copy_generation)
      stored = @document.updates.oldest_first.pluck(:id, :data)

      {
        type: "sync",
        generation: @generation,
        updates: readable(stored),
        # How far this page has read, for when it sends a merged copy back
        upto: stored.last&.first,
        seed: (seed_html if stored.empty?),
        compact: stored.size > COMPACT_AFTER
      }
    end
  end

  # The row that claims the first fill holds no change of its own, and Yjs
  # refuses to read an empty one
  def readable(stored)
    stored.map(&:last)
      .reject { |data| data.nil? || data.empty? }
      .map { |data| Base64.strict_encode64(data) }
  end

  # The text as it stands goes to the first page to open the document, which
  # builds the shared copy from it. The row claiming that is written here, so
  # two pages arriving together can't both fill the same document. A document
  # with nothing to read in it (new, or emptied: an editor leaves an empty
  # paragraph behind) has nothing to build from, and needs no claim.
  def seed_html
    html = @document.content&.body&.to_html.to_s
    return html if @document.content.to_plain_text.blank?

    @document.updates.create!(data: "", seed: true)
    @seeding = true
    html
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # The page that was handed the text left before any of it came back as a
  # change, so the copy it was to build was never made. Left alone, the claim
  # would have everyone after it join an empty copy and save that over the text.
  # So it goes the way of any copy that is thrown away: the next page is handed
  # the text, pages already waiting start over, and should this one come back
  # with what it built by itself, that is not added to someone else's.
  def give_up_seeding
    return unless @seeding && current_copy?
    return if @document.updates.where("length(data) > 0").exists?

    @document.reset_shared_copy!
  end

  # Runs the block when this page still writes in the document's copy, and says
  # whether it did. One transaction, and SQLite takes the write lock when one
  # starts, so the copy can't be thrown away between the check and the write.
  def in_this_copy
    Docs::Update.transaction do
      next false unless current_copy?

      yield
      true
    end
  end

  def current_copy?
    Docs::Document.where(id: @document.id).pick(:shared_copy_generation) == @generation
  end

  # Only the page that sent it hears: the copy it writes in is gone, and it is
  # to open the document again
  def start_over
    transmit({ type: "replaced" })
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
  # doesn't keep anyone else out — it's a sign, not a lock. One name is on it;
  # anyone else in the document takes it when it is free or has gone stale.
  def hold_editing_open
    taken = Docs::Document.where(id: @document.id)
      .where("locked_by_id IS NULL OR locked_at < ? OR locked_by_id = ?", Docs::Document::LOCK_TIMEOUT.ago, current_user.id)
      .update_all(locked_by_id: current_user.id, locked_at: Time.current)

    announce_editing(current_user.name) if taken.positive? && !@holding
    @holding = taken.positive?
    @held_at = Time.current
  end

  # The same, for what happens all the time: once it's ours, saying so again
  # can wait a little
  def keep_editing_open
    hold_editing_open unless @holding && @held_at > HOLD_EVERY.ago
  end

  # The sign only comes down when the last one leaves: with someone else still
  # in the document it goes on in their name
  def release_editing
    held = Docs::Document.where(id: @document.id, locked_by_id: current_user.id)
    heir = User.find_by(id: DocumentPresence.others(@document.id, current_user.id).first)

    if heir
      announce_editing(heir.name) if held.update_all(locked_by_id: heir.id, locked_at: Time.current).positive?
    elsif held.update_all(locked_by_id: nil, locked_at: nil).positive?
      announce_editing(nil)
    end
  end

  # Two audiences: whoever is reading this document (DocumentChannel) and the
  # documents list, where a card says who is writing (DocsChannel).
  def announce_editing(user_name)
    payload = { type: user_name ? "locked" : "unlocked", user_name: user_name }.compact

    DocumentChannel.broadcast_to(@document, payload)
    DocsChannel.broadcast_to(@document.tool, payload.merge(document_id: @document.id))
  end
end
