# frozen_string_literal: true

require "test_helper"

module Mails
  class RecipientSuggestionsTest < ActiveSupport::TestCase
    setup do
      @account = mails_accounts(:primary)
      @suggestions = RecipientSuggestions.new(@account)
    end

    test "mail of the last weeks counts for more than mail of long ago" do
      write_to "old@example.org", times: 3, days_ago: 400
      write_to "new@example.org", times: 1, days_ago: 3

      assert_equal [ "new@example.org", "old@example.org" ], addresses_for("example.org")
    end

    test "among people written to as lately, the one written to most comes first" do
      write_to "rare@example.org", times: 1, days_ago: 5
      write_to "often@example.org", times: 4, days_ago: 5

      assert_equal [ "often@example.org", "rare@example.org" ], addresses_for("example.org")
    end

    test "people in Cc and Bcc count too, whatever case their address was written in" do
      @account.messages.create!(message_id: "<cc@example.com>", folder: "Sent", from_address: @account.email_address, thread_id: "cc",
        to_addresses: [ "Kim@Example.com" ].to_json, cc_addresses: [ "kim@example.com", "lou@example.com" ].to_json, bcc_addresses: [ "max@example.com" ].to_json, sent_at: 1.day.ago)

      found = @suggestions.search("example.com").index_by(&:address)
      assert_equal 8, found["kim@example.com"].score
      assert_equal 4, found["lou@example.com"].score
      assert_equal 4, found["max@example.com"].score
    end

    test "someone is found by a name they were never written to with" do
      write_to "sender@example.com", times: 1, days_ago: 1

      found = @suggestions.search("friendly").sole
      assert_equal [ "sender@example.com", "Friendly Sender", 4 ], [ found.address, found.name, found.score ]
    end

    test "what begins a name or an address comes before what is only somewhere in it" do
      write_to "joanna@example.com", times: 9, days_ago: 1
      @account.contacts.create!(email_address: "ann@example.com", name: "Ann Lee")
      @account.contacts.create!(email_address: "lee@example.com", name: "Lee Annis")

      assert_equal [ "ann@example.com", "lee@example.com", "joanna@example.com" ], addresses_for("ann")
    end

    test "people who only wrote to the account come after the people it writes to" do
      write_to "sender-of-old@example.org", times: 1, days_ago: 500

      assert_equal [ "sender-of-old@example.org", "sender@example.com" ], addresses_for("sender")
    end

    test "the account's own address, nothing typed, and what is no address are left out" do
      write_to "undisclosed-recipients@", times: 1, days_ago: 1
      write_to @account.email_address, times: 1, days_ago: 1

      assert_empty addresses_for("undisclosed")
      assert_not_includes addresses_for("test"), @account.email_address
      assert_empty addresses_for("  ")
      assert_empty addresses_for("100%_")
    end

    test "a list of people that was saved wrongly doesn't stop the search" do
      write_to "ann@example.com", times: 1, days_ago: 1
      @account.messages.sent.update_all(cc_addresses: "not json")

      assert_equal [ "ann@example.com" ], addresses_for("ann")
    end

    private

    def addresses_for(query)
      @suggestions.search(query).map(&:address)
    end

    def write_to(address, times:, days_ago:)
      times.times do |time|
        @account.messages.create!(message_id: "<to-#{address}-#{time}@example.com>", folder: "Sent", subject: "Note", read: true,
          from_address: @account.email_address, to_addresses: [ address ].to_json, sent_at: (days_ago + time).days.ago, thread_id: "to-#{address}-#{time}")
      end
    end
  end
end
