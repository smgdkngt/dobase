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

      test "the text part of a draft keeps its paragraphs, lists and quote" do
        post tool_mail_drafts_path(@tool), params: {
          to: "ann@example.com", subject: "Re: Plans", in_reply_to: "<msg-001@example.com>",
          body: "<p>Yes.</p><ul><li>Thursday</li></ul><p>On Mon, Ann wrote:</p><blockquote><p>Lunch?</p><p>Or dinner?</p></blockquote>"
        }

        draft = ::Mails::Message.drafts.order(:created_at).last
        assert_equal "Yes.\n\n- Thursday\n\nOn Mon, Ann wrote:\n\n> Lunch?\n>\n> Or dinner?", draft.body_plain
      end

      test "update replaces the draft with the compose form" do
        draft = mails_messages(:draft_message)

        patch tool_mail_draft_path(@tool, draft), params: { to: "other@example.com", cc: "team@example.com", bcc: "", subject: "Changed", body: "<p>New</p>" }

        assert_redirected_to new_tool_mail_path(@tool, draft_id: draft.id)
        draft.reload
        assert_equal [ [ "other@example.com" ], [ "team@example.com" ], "Changed", "<p>New</p>" ],
          [ draft.to_addresses_list, draft.cc_addresses_list, draft.subject, draft.body_html ]
      end

      # What the compose page saves by itself while someone writes: the draft here is current
      # at once, the server's copy follows when the writing has paused
      test "an autosave answers with the draft and copies it to the server a while later" do
        freeze_time do
          post tool_mail_drafts_path(@tool), params: { to: "friend@example.com", subject: "Plans", body: "<p>Hi</p>", autosave: "1" },
            headers: { "Accept" => "application/json" }

          assert_response :created
          draft = ::Mails::Message.drafts.find(response.parsed_body["id"])
          assert_equal "Plans", draft.subject
          assert_enqueued_with job: SyncDraftJob, args: [ draft.id, { version: draft.sync_version } ], at: SyncDraftJob::AUTOSAVE_WAIT.from_now
        end
      end

      test "an autosave of a draft keeps it current and puts off its copy to the server" do
        draft = mails_messages(:draft_message)

        freeze_time do
          patch tool_mail_draft_path(@tool, draft), params: { subject: "Changed", body: "<p>New</p>", autosave: "1" },
            headers: { "Accept" => "application/json" }

          assert_response :ok
          assert_equal [ draft.id, "Changed" ], [ response.parsed_body["id"], draft.reload.subject ]
          assert_enqueued_with job: SyncDraftJob, args: [ draft.id, { version: draft.sync_version } ], at: SyncDraftJob::AUTOSAVE_WAIT.from_now
        end
      end

      test "an autosave of a draft that was sent or deleted elsewhere is not found" do
        draft = mails_messages(:draft_message)
        draft.update!(draft: false, folder: "Sent")

        patch tool_mail_draft_path(@tool, draft), params: { subject: "Changed", autosave: "1" }, headers: { "Accept" => "application/json" }

        assert_response :not_found
        assert_no_enqueued_jobs only: SyncDraftJob
      end

      test "Save Draft still copies the draft to the server right away" do
        draft = mails_messages(:draft_message)

        patch tool_mail_draft_path(@tool, draft), params: { subject: "Changed" }

        assert_enqueued_with job: SyncDraftJob, args: [ draft.id ]
      end
    end
  end
end
