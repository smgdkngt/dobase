# frozen_string_literal: true

module Mails
  module Idle
    RECENTLY_USED = 24.hours
    LOOK_AGAIN = 1.minute
    PER_HOST = ENV.fetch("MAIL_IDLE_PER_HOST", 10).to_i
    TOTAL = ENV.fetch("MAIL_IDLE_MAX", 50).to_i

    @watchers = {}
    @lock = Mutex.new

    class << self
      def enabled?
        !Demo.enabled? && ENV["MAIL_IDLE"] != "false"
      end

      def start
        return unless enabled?

        @wake = Thread::Queue.new
        @supervisor = Thread.new do
          Thread.current.name = "mail-idle"
          until @wake.closed?
            begin
              look
            rescue StandardError => error
              Rails.error.report(error, handled: true)
            end
            @wake.pop(timeout: LOOK_AGAIN.to_f)
          end
        end
      end

      def stop
        @wake&.close
        @supervisor&.join(5)
        @lock.synchronize { @watchers.each_value(&:stop).clear }
      end

      def look
        wanted = Rails.application.executor.wrap { wanted_account_ids }
        @lock.synchronize do
          (@watchers.keys - wanted).each { |id| @watchers.delete(id).stop }
          @watchers.reject! { |_id, watcher| !watcher.alive? && !watcher.stopped? }
          (wanted - @watchers.keys).each { |id| @watchers[id] = IdleWatcher.new(id).start }
        end
      end

      def watching = @lock.synchronize { @watchers.keys }

      def wanted_account_ids
        accounts = Mails::Account
          .joins(tool: :collaborators)
          .where(collaborators: { last_seen_at: RECENTLY_USED.ago.. })
          .group("mail_accounts.id")
          .order(Arel.sql("MAX(collaborators.last_seen_at) DESC"))
          .select("mail_accounts.*")
        on_host = Hash.new(0)
        accounts.reject(&:waiting_after_refused_login?)
          .select { |account| (on_host[account.imap_host] += 1) <= PER_HOST }
          .first(TOTAL).map(&:id)
      end
    end
  end
end
