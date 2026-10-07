# frozen_string_literal: true

require "test_helper"

module Mails
  class RecipientTest < ActiveSupport::TestCase
    test "a field's text is taken apart at commas, semicolons and lines" do
      recipients = Recipient.parse("Ann Lee <ann@example.com>, joe@example.com; <kim@example.com>\nlou@example.com,, ")

      assert_equal [ "ann@example.com", "joe@example.com", "kim@example.com", "lou@example.com" ], recipients.map(&:address)
      assert_equal [ "Ann Lee", nil, nil, nil ], recipients.map(&:name)
      assert_empty Recipient.parse(nil)
    end

    test "a quoted name keeps its comma" do
      recipient = Recipient.parse('"Lee, Ann" <ann@example.com>, joe@example.com').first

      assert_equal "Lee, Ann", recipient.name
      assert_equal "ann@example.com", recipient.address
      assert_equal '"Lee, Ann" <ann@example.com>', recipient.to_s
    end

    test "what is no address is kept as it was typed, and is not valid" do
      recipients = Recipient.parse("nobody, Ann <broken, ann@example.com")

      assert_equal [ "nobody", "Ann <broken", "ann@example.com" ], recipients.map(&:address)
      assert_equal [ false, false, true ], recipients.map(&:valid?)
      assert_equal "nobody", recipients.first.to_s
    end

    test "a name with letters of another alphabet goes with its address" do
      recipient = Recipient.from("Zoë Ex <zoe@example.com>")

      assert_equal [ "zoe@example.com", "Zoë Ex" ], [ recipient.address, recipient.name ]
    end
  end
end
