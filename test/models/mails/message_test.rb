# frozen_string_literal: true

require "test_helper"

module Mails
  class MessageTest < ActiveSupport::TestCase
    include ActionCable::TestHelper
    setup do
      @message = mails_messages(:inbox_unread)
    end

    test "remembers when a message went to the trash, and forgets it on restore" do
      freeze_time do
        @message.update!(trashed: true)
        assert_equal Time.current, @message.trashed_at
      end

      travel 1.day do
        @message.update!(read: true)
        assert_equal 1.day.ago, @message.reload.trashed_at
      end

      @message.update!(trashed: false)
      assert_nil @message.reload.trashed_at
    end

    test "a reply references the message's ancestors and then the message" do
      assert_equal "<msg-001@example.com>", @message.reply_references

      @message.in_reply_to = "<parent@example.com>"
      assert_equal "<parent@example.com> <msg-001@example.com>", @message.reply_references

      @message.references = "<root@example.com> <parent@example.com>"
      assert_equal "<root@example.com> <parent@example.com> <msg-001@example.com>", @message.reply_references
    end

    test "an Outlook picture saved before Content-IDs were kept is found by its file name" do
      @message.update!(body_html: %(<img src="cid:image001.png@01DD4FFC.8E9C6530"><img src="cid:missing@example.com">))
      logo = @message.attachments.create!(filename: "image001.png", content_type: "image/png", file_size: 3)
      logo.file.attach(io: StringIO.new("PNG"), filename: "image001.png", content_type: "image/png")

      assert_equal({ "image001.png@01dd4ffc.8e9c6530" => logo }, @message.inline_images)
      assert_equal %(<img src="data:image/png;base64,UE5H"><img src="cid:missing@example.com">), @message.body_html_with_inline_images
      assert_empty @message.listed_attachments
    end

    test "a picture whose file is gone from storage is left out, and the message still shows" do
      @message.update!(body_html: %(<p>Hello</p><img src="cid:logo@example.com">))
      logo = @message.attachments.create!(filename: "logo.png", content_type: "image/png", file_size: 3, content_id: "logo@example.com")
      logo.file.attach(io: StringIO.new("PNG"), filename: "logo.png", content_type: "image/png")
      logo.file.blob.service.delete(logo.file.blob.key)

      assert_equal %(<p>Hello</p><img src="cid:logo@example.com">), @message.body_html_with_inline_images
    end

    test "reading a message tells its tool's people how much unread mail they have left" do
      user = @message.account.tool.users.first
      unread = user.unread_mail_count

      assert_broadcast_on("notifications:#{user.id}", { type: "unread_mail", count: unread - 1 }) do
        @message.mark_as_read!
      end
    end

    test "a draft goes out with its quote as it was changed, kept the way mail is shown" do
      draft = mails_messages(:draft_message)
      @message.update!(body_html: "<p>Lunch?</p><p>The password is hunter2</p>")
      draft.update!(quoted_message: @message, quote_html: %(<p>Ann wrote:</p><blockquote type="cite"><p onclick="steal()">Lunch?</p><script>steal()</script></blockquote>))

      assert_equal %(<p>Ann wrote:</p><blockquote type="cite"><p>Lunch?</p></blockquote>), draft.quote_html
      assert Mails::Quote.of(draft).edited?
      assert_equal %(#{draft.body_html}<p>Ann wrote:</p><blockquote type="cite"><p>Lunch?</p></blockquote>), draft.outgoing_html

      # Nothing given is the quoted mail as it was written again
      draft.update!(quote_html: "")
      assert_nil draft.quote_html
      assert_not Mails::Quote.of(draft).edited?
      assert_match "hunter2", draft.outgoing_html
    end

    test "a quote that was changed is nothing without the mail it quotes" do
      draft = mails_messages(:draft_message)
      draft.update!(quote_html: "<p>Lunch?</p>")

      assert_nil Mails::Quote.of(draft)
      assert_equal draft.body_html, draft.outgoing_html
    end

    test "a draft whose quoted mail was deleted has no quote" do
      draft = mails_messages(:draft_message)
      draft.update!(quoted_message: @message)

      @message.destroy

      assert_nil draft.reload.quoted_message
      assert_equal draft.body_html, draft.outgoing_html
    end
  end
end
