# frozen_string_literal: true

module Mails
  class IdleWatcher
    class NoIdle < StandardError; end

    RENEW = 10.minutes
    FOLLOW_UP = 20.seconds
    FOLLOW_UPS = 5
    BACKOFF = [ 10.seconds, 30.seconds, 1.minute, 2.minutes, 5.minutes ].freeze
    CHANGES = %w[EXISTS EXPUNGE FETCH].freeze

    attr_reader :account_id

    def initialize(account_id, debounce: 2.seconds)
      @account_id = account_id
      @debounce = debounce
      @wake = Thread::Queue.new
      @stopped = false
      @failures = 0
    end

    def start
      @thread = Thread.new do
        Thread.current.name = "mail-idle-#{account_id}"
        run
      end
      self
    end

    def alive? = @thread&.alive?

    def stop
      @stopped = true
      @wake << :stop
      @imap&.disconnect rescue nil
      @thread&.join(5)
    end

    def stopped? = @stopped

    def run
      until stopped?
        begin
          watch
          @failures = 0
        rescue ::ImapSyncService::AuthenticationError
          rest(EncryptedPassword::LOGIN_RETRY)
        rescue NoIdle
          rest(1.hour)
        rescue ::ImapSyncService::ConnectionError, Net::IMAP::Error, *::ImapSyncService::UNREACHABLE => error
          break if stopped?

          Rails.logger.info("Mail idle for account #{account_id} lost its connection: #{error.class}: #{error.message}")
          rest(backoff)
        rescue StandardError => error
          break if stopped?

          Rails.error.report(error, handled: true, context: { mail_account_id: account_id })
          rest(backoff)
        end
      end
    end

    private
      def watch
        account = in_app { Mails::Account.find_by(id: account_id) }
        return @stopped = true unless account
        raise ::ImapSyncService::AuthenticationError if in_app { account.waiting_after_refused_login? }

        ::ImapSyncService.new(account).with_connection do |imap|
          @imap = imap
          raise NoIdle unless imap.capable?("IDLE")

          imap.select("INBOX")
          @failures = 0
          sync
          idle(imap) until stopped?
        ensure
          @imap = nil
        end
      end

      def idle(imap)
        changed = false
        exists = nil
        imap.idle(@pending ? FOLLOW_UP : RENEW) do |response|
          next unless response.is_a?(Net::IMAP::UntaggedResponse) && CHANGES.include?(response.name)

          changed = true
          exists = response.data if response.name == "EXISTS"
          imap.idle_done
        end
        return if stopped?

        if changed
          rest(@debounce)
          sync
          uid = uid_of(imap, exists) if exists
          @pending = { uid: uid, follow_ups: 0 } if uid
        elsif @pending
          follow_up
        end
      end

      def follow_up
        if in_app { Mails::Message.where(mail_account_id: account_id, folder: "INBOX").maximum(:uid).to_i } >= @pending[:uid].to_i ||
           @pending[:follow_ups] >= FOLLOW_UPS
          @pending = nil
        else
          @pending[:follow_ups] += 1
          sync
        end
      end

      def uid_of(imap, sequence_number)
        imap.fetch(sequence_number, [ "UID" ])&.last&.attr&.fetch("UID", nil)
      rescue Net::IMAP::NoResponseError, Net::IMAP::BadResponseError
        nil
      end

      def sync
        in_app { SyncEmailsJob.perform_later(account_id) }
      end

      def backoff
        base = BACKOFF[[ @failures, BACKOFF.size - 1 ].min]
        @failures += 1
        base + rand * base / 2
      end

      def rest(seconds)
        @wake.pop(timeout: seconds.to_f) unless stopped?
      end

      def in_app(&block)
        Rails.application.executor.wrap(&block)
      end
  end
end
