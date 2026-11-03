# frozen_string_literal: true

require "test_helper"

module Tools
  # A search in a mailbox looks in every folder, says where each result is, and can be
  # narrowed to one folder and ordered by date
  class MailSearchTest < ActionDispatch::IntegrationTest
    setup do
      sign_in_as users(:one)
      @tool = tools(:my_mail)
      @account = mails_accounts(:primary)
      @account.update!(synced_folders: %w[INBOX Sent Receipts Receipts/2026].to_json)
      @receipt = @account.messages.create!(message_id: "<harbour-1@example.com>", folder: "Receipts/2026", subject: "Harbour fees",
        from_address: "port@example.com", sent_at: 2.days.ago, read: true)
      @sent = @account.messages.create!(message_id: "<harbour-2@example.com>", folder: "Sent", subject: "Re: moorings",
        body_plain: "See you at the harbour", from_address: @account.email_address, sent_at: 1.day.ago, read: true)
      @trashed = @account.messages.create!(message_id: "<harbour-3@example.com>", folder: "INBOX", subject: "Harbour spam",
        trashed: true, sent_at: Time.current)
    end

    test "a search looks in every folder but the trash, and says where each result is" do
      get tool_mails_path(@tool, folder: "inbox", q: "harbour")

      assert_response :success
      assert_select ".mail-list-item", 2
      assert_select "#conversation-#{@receipt.id} .mail-list-folder", text: "2026"
      assert_select "#conversation-#{@sent.id} .mail-list-folder", text: "Sent"
      assert_select "#conversation-#{@trashed.id}", 0
      assert_select ".mail-search-pick", text: /All folders/
      # A result is opened in its own folder
      assert_select "#conversation-#{@sent.id} a[href*='folder=sent']"
    end

    test "the best match comes first, or the newest" do
      get tool_mails_path(@tool, q: "harbour")
      assert_equal [ @receipt.id, @sent.id ], css_select(".mail-list-item").map { |item| item["id"].delete_prefix("conversation-").to_i }

      get tool_mails_path(@tool, q: "harbour", sort: "date")
      assert_equal [ @sent.id, @receipt.id ], css_select(".mail-list-item").map { |item| item["id"].delete_prefix("conversation-").to_i }
      assert_select ".mail-search-sort a[aria-current]", text: "Newest"
    end

    test "a search narrowed to one folder, the trash included" do
      get tool_mails_path(@tool, q: "harbour", in: "Receipts/2026")
      assert_select ".mail-list-item", 1
      assert_select "#conversation-#{@receipt.id}"

      get tool_mails_path(@tool, q: "harbour", in: "trash")
      assert_select ".mail-list-item", 1
      assert_select "#conversation-#{@trashed.id}"
    end

    test "the pages and the menu keep the query, the folder and the order" do
      get tool_mails_path(@tool, q: "harbour", sort: "date")

      assert_select "#mail-search-in-#{@tool.id} a[href*='in=Receipts%2F2026'][href*='sort=date'][href*='q=harbour']"
      assert_select "form[action='#{tool_mails_path(@tool)}'] input[type=hidden][name=sort][value=date]"
    end

    test "the API says where each result is and what was searched" do
      get tool_mails_path(@tool, q: "harbour", format: :json)

      body = response.parsed_body
      assert_equal({ "query" => "harbour", "in" => "all", "sort" => "relevance" }, body["search"])
      assert_equal [ "Receipts/2026", "sent" ], body["conversations"].map { |conversation| conversation["folder"] }
    end

    test "what is picked in a search over every folder is archived from where each one is" do
      post tool_bulk_path(@tool), params: { message_ids: [ @receipt.id, @sent.id ], action_type: "archive", folder: "all" }

      assert @receipt.reload.archived?
      assert @sent.reload.archived?
    end
  end
end
