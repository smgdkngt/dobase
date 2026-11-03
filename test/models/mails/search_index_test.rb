# frozen_string_literal: true

require "test_helper"

module Mails
  class SearchIndexTest < ActiveSupport::TestCase
    setup { @account = mails_accounts(:primary) }

    def found(query)
      @account.messages.search(query).pluck(:subject)
    end

    test "every word must be there, as a word or the start of one" do
      assert_equal [ "Welcome to Dobase" ], found("welc dob")
      assert_empty found("welcome nowhere")
    end

    test "quoted words are looked for as they stand, one after the other" do
      assert_equal [ "Welcome to Dobase" ], found('"welcome to"')
      assert_empty found('"to welcome"')
    end

    test "what is typed is never taken as FTS5's own syntax" do
      assert_equal "\"welcome\"* \"OR\"* \"dobase\"*", SearchIndex.query("welcome OR dobase")
      assert_equal "\"a b\"*", SearchIndex.query("a:b")
      assert_nil SearchIndex.query(%( "" *** ))
      assert_empty found("***")
      assert_nothing_raised { found(%(NEAR( "x" ) AND -y ^z)) }
    end

    test "accents don't matter" do
      message = @account.messages.create!(message_id: "<cafe@example.com>", folder: "INBOX", subject: "Koffie in het café", sent_at: Time.current)

      assert_includes @account.messages.search("cafe").to_a, message
    end

    test "a new message is found by its people, its text and its files" do
      message = @account.messages.create!(message_id: "<invoice@example.com>", folder: "Receipts", subject: "March",
        from_name: "Ann Lee", from_address: "ann@supplier.example", to_addresses: [ "books@example.com" ].to_json,
        body_plain: "Please find the invoice attached.", sent_at: Time.current)
      message.attachments.create!(filename: "factuur-2026-03.pdf", content_type: "application/pdf")

      [ "Ann", "supplier", "books@example.com", "invoice attached", "factuur 2026" ].each do |query|
        assert_includes @account.messages.search(query).to_a, message, "found by #{query}"
      end
    end

    test "a changed subject is found by its new words, and a removed message is not found" do
      message = mails_messages(:inbox_read)
      message.update!(subject: "Quarterly figures")

      assert_equal [ "Quarterly figures" ], found("quarterly")

      message.destroy!
      assert_empty found("quarterly")
    end

    test "a match in the subject ranks above one in the text" do
      @account.messages.create!(message_id: "<text@example.com>", folder: "INBOX", subject: "Hello", body_plain: "about the harbour", sent_at: Time.current)
      @account.messages.create!(message_id: "<subject@example.com>", folder: "INBOX", subject: "The harbour", body_plain: "Hi", sent_at: 1.year.ago)

      ranked = @account.messages.search("harbour").order("mail_hits.hit_score").pluck(:subject)
      assert_equal [ "The harbour", "Hello" ], ranked
    end
  end
end
