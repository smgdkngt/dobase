# frozen_string_literal: true

require "test_helper"

module Mails
  class AccountTest < ActiveSupport::TestCase
    setup do
      @account = mails_accounts(:primary)
    end

    test "the archive folder is synced with the account's own folders, when the server has it" do
      @account.update!(synced_folders: %w[INBOX Sent Archive Clients].to_json, archive_folder: "Archive")
      assert_equal %w[Clients Archive], @account.other_folders_to_sync

      @account.update!(archive_folder: "Done")
      assert_equal %w[Archive Clients], @account.other_folders_to_sync
    end
  end
end
