# frozen_string_literal: true

module Mails
  # What one run of the mail sync saw happen on the server, written down as events
  # (Event) once the run is over: mail that came in, and mail another mail program
  # moved, archived or deleted.
  #
  # The sync itself only sees rows come and go, which is not the same thing:
  #
  # - A new row is not new mail. A folder's first sync brings its old mail, a big
  #   folder fills in over several runs, and mail imported by another program is
  #   as old as it says. Mail has come in when its folder gave it a higher number
  #   (UID) than any it had, and the server took it in since the last sync.
  # - Mail moved elsewhere is a row gone from one folder and a new row in another,
  #   in whichever order the folders are synced. So nothing is decided before the
  #   end of the run: gone here and new there is one move. Gone and nowhere else
  #   is deleted, when the run got through every folder.
  # - A copy is nothing. Mail archived here keeps its row and gets a second one in
  #   the server's archive folder; some servers show one message in several folders.
  class SyncEvents
    # The servers' clocks and this one's needn't agree
    CLOCK_SLACK = 1.hour
    # Mail that turns up in these has not come in: it was sent, written or thrown away
    NO_INBOX = [ "Sent", "Drafts", Account::TRASH ].freeze

    Arrival = Struct.new(:message, :received_at, :new_number)
    Departure = Struct.new(:message)

    def initialize(account)
      @account = account
      @synced_before = account.last_synced_at
      @highest = {}
      @arrived = []
      @left = []
    end

    # Before a folder is synced: the highest number it has given so far
    def syncing(folder)
      @highest[folder] = @account.messages.where(folder: folder).maximum(:uid) unless @highest.key?(folder)
    end

    # A row the sync made: `received_at` is when the server took the mail in (INTERNALDATE)
    def arrived(message, received_at)
      highest = @highest[message.folder]
      @arrived << Arrival.new(message, time_of(received_at), highest.nil? || message.uid.to_i > highest)
    end

    # A row the sync removed, because its folder no longer has the mail
    def left(message)
      @left << Departure.new(message)
    end

    # `complete`: the run got through every folder, so mail that is gone is gone
    def record(complete:)
      departures = @left.reject { |departure| departure.message.draft? }.group_by { |departure| departure.message.message_id }

      @arrived.sort_by { |arrival| arrival.received_at || Time.current }.each do |arrival|
        message = arrival.message
        if (departure = departures.delete(message.message_id)&.first)
          record_move(message, departure.message.folder)
        elsif !copy?(message) && new_mail?(arrival)
          message.record_event(:received)
        end
      end

      return unless complete

      departures.each_value do |gone|
        message = gone.first.message
        # Out of the trash and nowhere else: the server emptied it, which was said when it went in
        next if message.folder == Account::TRASH || copy?(message)

        message.record_event(:deleted)
      end
    end

    private
      def record_move(message, was_in)
        kind = if message.folder == Account::TRASH then :deleted
        elsif message.folder == @account.archive_folder.presence then :archived
        elsif was_in == @account.archive_folder.presence then :unarchived
        else :moved
        end
        message.record_event(kind, moved_from: was_in)
      end

      def new_mail?(arrival)
        return false if @synced_before.nil? || !arrival.new_number
        return false if arrival.message.folder.in?(NO_INBOX) || arrival.message.folder == @account.archive_folder.presence

        arrival.received_at.nil? || arrival.received_at >= @synced_before - CLOCK_SLACK
      end

      # The same mail in another folder too. Mail to yourself is in Sent and comes in as well.
      def copy?(message)
        @account.messages.where(message_id: message.message_id).where.not(id: message.id)
          .where.not(folder: %w[Sent Drafts]).exists?
      end

      def time_of(value)
        value.is_a?(Time) ? value : Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end
  end
end
