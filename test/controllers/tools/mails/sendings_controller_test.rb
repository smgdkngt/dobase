# frozen_string_literal: true

require "test_helper"

module Tools
  module Mails
    class SendingsControllerTest < ActionDispatch::IntegrationTest
      setup do
        sign_in_as users(:one)
        @tool = tools(:my_mail)
        @account = @tool.mail_account
        @draft = mails_messages(:draft_message)
      end

      test "mail sent off waits a moment, with Undo beside it, which makes it the draft it was and opens it in the compose page" do
        post tool_mails_path(@tool), params: { draft_id: @draft.id, folder: "inbox", to: "friend@example.com", subject: "Plans", body: "<p>Hi there</p>" }

        job = enqueued_jobs.find { _1["job_class"] == "SendMailJob" }
        assert_in_delta SendMailJob::UNDO_TIME.from_now.to_f, job["scheduled_at"].to_time.to_f, 2
        follow_redirect!
        assert_select ".mail-sending-note a[href='#{tool_mail_sending_path(@tool, @draft, folder: "inbox")}'][data-turbo-method=delete][data-hotkey=z]", text: "Undo"

        delete tool_mail_sending_path(@tool, @draft, folder: "inbox")

        assert_redirected_to new_tool_mail_path(@tool, draft_id: @draft.id, folder: "inbox")
        assert_equal [ "Drafts", true, false ], @draft.reload.values_at(:folder, :draft, :sending)
        assert_enqueued_with(job: SyncDraftJob, args: [ @draft.id ])

        follow_redirect!
        assert_select "input[name=draft_id][value='#{@draft.id}']"
        assert_select "input[name=subject][value=Plans]"
        assert_includes response.body, "Hi there"

        deliveries = capture_smtp_deliveries { perform_enqueued_jobs(only: SendMailJob) }
        assert_empty deliveries, "taken back, it doesn't go out"
        assert @draft.reload.draft?
      end

      test "a mail tool without an account has nothing to take back" do
        tool = Tool.create!(name: "New mail", tool_type: tool_types(:mail), owner: users(:one))

        delete tool_mail_sending_path(tool, @draft, folder: "inbox")

        assert_redirected_to tool_mails_path(tool)
        assert_equal [ "Drafts", true ], @draft.reload.values_at(:folder, :draft)
      end

      test "once the job has it, it's too late, and it goes out" do
        @draft.start_sending!
        assert @draft.claim_for_sending!

        delete tool_mail_sending_path(@tool, @draft, folder: "inbox")

        assert_equal "Too late to undo: it's on its way.", flash[:alert]
        assert_equal [ "Sent", false, true ], @draft.reload.values_at(:folder, :draft, :sending)
      end

      test "mail that has gone out can't be taken back, nor can mail of a tool someone isn't on" do
        sent = mails_messages(:sent_message)
        delete tool_mail_sending_path(@tool, sent)
        assert_not sent.reload.draft?

        other = mails_messages(:other_inbox)
        delete tool_mail_sending_path(tools(:other_mail), other)
        assert_redirected_to root_path
      end
    end
  end
end
