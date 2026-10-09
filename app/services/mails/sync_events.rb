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
  #   is deleted, when the run got through every folder and read all that had
  #   come into each. A run reads so much of a folder and no more, and mail moved
  #   into the part it didn't read would look deleted: then nothing is said of
  #   mail that is gone, in this run or a later one (which finds old mail).
  # - A copy is nothing. Mail archived here keeps its row and gets a second one in
  #   the server's archive folder; some servers show one message in several folders.
  #
  # Mail is told apart by its Message-ID, which its sender wrote. Mail that comes
  # in under the Message-ID of mail the account already has reads as a copy of
  # it, and gives no event. It is in the mailbox like any other.
  class SyncEvents
    # The servers' clocks and this one's needn't agree
    CLOCK_SLACK = 1.hour
    # Mail that turns up in these has not come in: it was sent, written or thrown away
    NO_INBOX = [ "Sent", "Drafts", Account::TRASH ].freeze

    # What is kept of a message until the run is over: enough to tell it apart and to
    # say what it was, without what it says. A run can see thousands.
    KEPT = %w[id mail_account_id message_id folder uid draft from_address from_name subject].freeze

    Arrival = Struct.new(:message, :received_at, :new_number)

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
      @arrived << Arrival.new(kept(message), time_of(received_at), highest.nil? || message.uid.to_i > highest)
    end

    # A row the sync removed, because its folder no longer has the mail
    def left(message)
      @left << kept(message)
    end

    # Mail a folder has that this run didn't fetch (ImapSyncService reads so much per
    # run, and of a very big folder only the last months). Under the numbers the folder
    # had, it is old mail still to come into view. Above them it came into the folder
    # since, from somewhere: mail that left another folder may be among it.
    def unread(folder, uids)
      highest = @highest[folder]
      @unread ||= uids.any? { |uid| highest.nil? || uid > highest }
    end

    # `complete`: the run got through every folder, so mail that is gone is gone
    def record(complete:)
      Event.signal_once { record_all(complete: complete) }
    end

    private
      def record_all(complete:)
        departures = @left.reject(&:draft?).group_by(&:message_id)

        @arrived.sort_by { |arrival| arrival.received_at || Time.current }.each do |arrival|
          message = arrival.message
          if (departure = departures.delete(message.message_id)&.first)
            record_move(message, departure.folder)
          elsif new_mail?(arrival) && !copy?(message)
            message.record_event(:received)
          end
        end

        return unless complete && !@unread

        departures.each_value do |gone|
          message = gone.first
          # Out of the trash and nowhere else: the server emptied it, which was said when it went in
          next if message.folder == Account::TRASH || copy?(message)

          message.record_event(:deleted)
        end
      end

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

      def kept(message)
        Message.instantiate(message.attributes.slice(*KEPT)).tap { |light| light.account = @account }
      end

      def time_of(value)
        value.is_a?(Time) ? value : Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end
  end
end
