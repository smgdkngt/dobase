# frozen_string_literal: true

require "net/imap"

# An IMAP server for tests. It lists its folders, finds messages by Message-ID
# and records what it's asked to do. `connect_to_imap` sends connections to it.
class FakeImapServer
  attr_reader :selected, :searched, :stored, :copied, :lists

  # message_ids: { [folder, "<message-id>"] => [uid, ...] }
  def initialize(folders: [ "INBOX" ], message_ids: {})
    @folders = folders
    @message_ids = message_ids
    @selected, @searched, @stored, @copied, @lists = [], [], [], [], 0
  end

  def login(_username, _password) = nil
  def logout = nil
  def disconnect = nil
  def expunge = nil

  def list(_reference, _pattern)
    @lists += 1
    @folders.map { |name| Net::IMAP::MailboxList.new([], "/", name) }
  end

  def select(folder) = @selected << folder
  def uid_store(uids, action, flags) = @stored << [ uids, action, flags ]
  def uid_copy(uids, folder) = @copied << [ uids, folder ]

  # Only knows searches for a Message-ID header, in the selected folder
  def uid_search(criteria)
    @searched << criteria
    @message_ids.fetch([ @selected.last, criteria.last ], [])
  end
end

module FakeImapServerHelper
  # Every IMAP connection made in the block goes to the server
  def connect_to_imap(server)
    Net::IMAP.singleton_class.define_method(:new) { |*, **| server }
    yield
  ensure
    Net::IMAP.singleton_class.remove_method(:new)
  end
end

ActiveSupport.on_load(:active_support_test_case) do
  include FakeImapServerHelper
end
