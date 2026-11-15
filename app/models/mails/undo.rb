# frozen_string_literal: true

module Mails
  # What was just done to mail (archived, trashed, moved, junk or not), kept in the Undo
  # button of the message that says so: signed, for one person in one mail tool, for a
  # few minutes. Undoing goes through the account's own methods, so the server is told
  # and an event is written as with anything else done to mail.
  #
  #   undo = Mails::Undo.record(account, :unarchive, messages, user: Current.user) { account.archive(_1) }
  #   Mails::Undo.find(token, account: account, user: Current.user)&.apply
  class Undo
    # unarchive: archived mail goes back where it was archived from.
    # put_back: mail that was trashed or moved goes back to the folder it was in, archived if it was.
    KINDS = %w[unarchive put_back].freeze
    EXPIRES_IN = 5.minutes
    # The token rides along in the flash, in the session's cookie
    LONGEST = 1800

    attr_reader :account, :kind, :places

    # Runs the block on the messages; it answers the ones it acted on. Where those were
    # before is what undoing puts them back to.
    def self.record(account, kind, messages, user:)
      messages = messages.to_a
      before = messages.to_h { |message| [ message.id, [ message.folder, message.archived? ] ] }
      done = yield(messages).to_a
      new(account, kind.to_s, done.map { |message| [ message.id, *before.fetch(message.id) { [ message.folder, message.archived? ] } ] }, user: user)
    end

    def self.verifier
      Rails.application.message_verifier("mail_undo")
    end

    def self.find(token, account:, user:)
      payload = verifier.verified(token.to_s, purpose: :undo)
      return unless payload.is_a?(Hash) && payload["tool"] == account.tool_id && payload["user"] == user.id && payload["kind"].in?(KINDS)

      places = payload["places"].flat_map do |where, ids|
        # A folder's name may have a bar in it, the mark after the last one never does
        folder, _, archived = where.rpartition("|")
        Array(ids).map { |id| [ id, folder.presence, archived == "1" ] }
      end
      new(account, payload["kind"], places, user: user)
    rescue ActiveSupport::MessageVerifier::InvalidSignature, NoMethodError, TypeError
      nil
    end

    def initialize(account, kind, places, user:)
      @account, @kind, @places, @user = account, kind, places, user
    end

    def any?
      places.any?
    end

    # Nil when there is nothing to undo, or too much to carry in the flash
    def token
      return unless any?

      grouped = places.group_by { |_, folder, archived| "#{folder}|#{archived ? 1 : 0}" }.transform_values { |each| each.map(&:first) }
      token = self.class.verifier.generate({ "tool" => account.tool_id, "user" => @user.id, "kind" => kind, "places" => grouped },
        purpose: :undo, expires_in: EXPIRES_IN)
      token if token.size <= LONGEST
    end

    # The messages as they are now, of the account only. Answers how many were put back.
    def apply
      messages = account.messages.where(id: places.map(&:first)).index_by(&:id)
      return 0 if messages.empty?

      case kind
      when "unarchive"
        account.unarchive(messages.values.select { |message| message.archived? || account.in_archive_folder?(message) })
      when "put_back"
        targets = places.to_h { |id, folder, archived| [ id, target_folder(folder, archived) ] }
        # Out of the trash straight to where it was, not by way of the inbox
        account.restore(messages.values.select(&:trashed?), folders: targets)
        places.each do |id, _, archived|
          message = messages[id]
          put_back(message, targets[id], archived) if message
        end
      end
      messages.size
    end

    private

    def target_folder(folder, archived)
      (account.archive_folder.presence if archived) || folder || "INBOX"
    end

    def put_back(message, target, archived)
      account.move([ message ], target) unless message.folder == target && !message.trashed?
      # Without an archive folder, archived mail is mail marked archived where it is
      account.archive([ message ]) if archived && account.archive_folder.blank?
    end
  end
end
