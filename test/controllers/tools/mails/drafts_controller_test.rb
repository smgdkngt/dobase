# frozen_string_literal: true

require "test_helper"

module Tools
  module Mails
    class DraftsControllerTest < ActionDispatch::IntegrationTest
      setup do
        sign_in_as users(:one)
        @tool = tools(:my_mail)
      end

      test "create saves the compose form as a draft and reopens it" do
        post tool_mail_drafts_path(@tool), params: {
          to: "friend@example.com, boss@example.com", cc: "", bcc: "", subject: "Plans", body: "<p>Hello <b>there</b></p>", in_reply_to: "<msg-001@example.com>"
        }

        draft = ::Mails::Message.drafts.order(:created_at).last
        assert_redirected_to new_tool_mail_path(@tool, draft_id: draft.id)
        assert_equal [ "friend@example.com", "boss@example.com" ], draft.to_addresses_list
        assert_nil draft.cc_addresses
        assert_equal [ "Plans", "Hello there", "<msg-001@example.com>" ], [ draft.subject, draft.body_plain, draft.in_reply_to ]
        assert_enqueued_with job: SyncDraftJob, args: [ draft.id ]
      end

      test "update replaces the draft with the compose form" do
        draft = mails_messages(:draft_message)

        patch tool_mail_draft_path(@tool, draft), params: { to: "other@example.com", cc: "team@example.com", bcc: "", subject: "Changed", body: "<p>New</p>" }

        assert_redirected_to new_tool_mail_path(@tool, draft_id: draft.id)
        draft.reload
        assert_equal [ [ "other@example.com" ], [ "team@example.com" ], "Changed", "<p>New</p>" ],
          [ draft.to_addresses_list, draft.cc_addresses_list, draft.subject, draft.body_html ]
      end
    end
  end
end
