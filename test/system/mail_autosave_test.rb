# frozen_string_literal: true

require "application_system_test_case"

# The compose form saves itself as a draft a few seconds after the last change, so a tab
# that hangs, a reload after a deploy or a phone that dies doesn't lose what was written
class MailAutosaveTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    sign_in_as(users(:one))
    @tool = tools(:my_mail)
    @account = @tool.mail_account
  end

  test "a message being written saves itself, and goes on saving into the same draft" do
    compose
    add_recipient "friend@example.com"
    find("input[name='subject']").set("Plans")
    write "Shall we meet on Friday?"

    assert_selector "[data-compose-target='saveStatus']", text: /\ASaved \d{1,2}:\d{2}/, wait: 10
    draft = @account.messages.drafts.find_by!(subject: "Plans")
    assert_equal [ "friend@example.com" ], draft.to_addresses_list
    assert_match "Shall we meet on Friday?", draft.body_html
    assert_selector "input[name=draft_id][value='#{draft.id}']", visible: :hidden
    assert_enqueued_with job: SyncDraftJob, args: [ draft.id, { version: draft.sync_version } ]

    write " Or Saturday."
    assert_db_change(-> { draft.reload.body_html.include?("Or Saturday.") }, timeout: 10)
    assert_equal 1, @account.messages.drafts.where(subject: "Plans").count
  end

  test "once it is saved, leaving asks nothing, and the draft is there with its text" do
    compose
    find("input[name='subject']").set("Plans")
    write "Shall we meet on Friday?"
    assert_selector "[data-compose-target='saveStatus']", text: "Saved", wait: 10

    # No question: a confirm would stop the visit and fail the test
    click_on "Project Board"
    assert_current_path tool_board_path(tools(:project_board)), wait: 10

    visit tool_mails_path(@tool, folder: "drafts")
    find(".mail-list-item", text: "Plans").click
    wait_for_compose_editor
    assert_selector "rhino-editor [contenteditable]", text: "Shall we meet on Friday?"
    assert_equal "Plans", find("input[name='subject']").value
  end

  test "a change since the last save still asks before leaving" do
    compose
    find("input[name='subject']").set("Plans")
    write "Shall we meet on Friday?"
    assert_selector "[data-compose-target='saveStatus']", text: "Saved", wait: 10

    slow_down_autosave
    write " Or Saturday."
    dismiss_confirm("You have an unsent message. Discard it?") { click_on "Project Board" }
    assert_selector "rhino-editor [contenteditable]", text: "Or Saturday."
  end

  test "a reload saves what isn't saved yet, and the draft has it" do
    compose
    slow_down_autosave
    find("input[name='subject']").set("Plans")
    write "Written just before the reload"

    # Headless Chrome reloads without asking; a browser that asks has the save on its way by then
    execute_script("location.reload()")

    assert_db_change(-> { @account.messages.drafts.find_by(subject: "Plans")&.body_html.to_s.include?("just before the reload") }, timeout: 10)
  end

  test "sent after it saved itself, the message goes out once and no draft is left" do
    compose
    add_recipient "friend@example.com"
    find("input[name='subject']").set("Plans")
    write "Shall we meet on Friday?"
    assert_selector "[data-compose-target='saveStatus']", text: "Saved", wait: 10
    draft = @account.messages.drafts.find_by!(subject: "Plans")

    deliveries = capture_smtp_deliveries do
      perform_enqueued_jobs(only: SendMailJob) do
        click_on "Send"
        assert_selector ".mail-detail-header h1", text: "Plans"
      end
    end

    assert_equal 1, deliveries.size
    assert_match "Shall we meet on Friday?", deliveries.sole[:message]
    assert_not @account.messages.drafts.exists?(subject: "Plans")
    assert_equal [ draft.id ], @account.messages.where(subject: "Plans").pluck(:id)
    # The draft's copy for the server, asked for by the save, finds a sent mail and leaves it be
    assert_nothing_raised { perform_enqueued_jobs(only: SyncDraftJob) }
  end

  test "Send pressed while a save is on its way waits for that save, and the mail goes out as written" do
    compose
    add_recipient "friend@example.com"
    find("input[name='subject']").set("Plans")
    write "Shall we meet on Friday?"
    assert_selector "[data-compose-target='saveStatus']", text: "Saved", wait: 10

    happened = Queue.new
    slow_save = Module.new do
      define_method(:update) do
        return super() unless params[:autosave]

        happened << :save_started
        sleep 1.5
        super().tap { happened << :save_done }
      end
    end
    sent = ->(*, payload) { happened << :send if payload[:controller] == "Tools::MailsController" && payload[:action] == "create" }
    Tools::Mails::DraftsController.prepend(slow_save)

    ActiveSupport::Notifications.subscribed(sent, "start_processing.action_controller") do
      write " Or Saturday."
      assert_equal :save_started, happened.pop(timeout: 10)
      deliveries = capture_smtp_deliveries do
        perform_enqueued_jobs(only: SendMailJob) do
          click_on "Send"
          assert_selector ".mail-detail-header h1", text: "Plans", wait: 10
        end
      end

      assert_equal [ :save_done, :send ], Array.new(2) { happened.pop(timeout: 10) }
      assert_match "Or Saturday.", deliveries.sole[:message]
    end
  ensure
    slow_save&.remove_method(:update)
  end

  test "Send pressed while a save hangs goes out after a few seconds anyway, and the save changes nothing" do
    compose
    add_recipient "friend@example.com"
    find("input[name='subject']").set("Plans")
    write "Shall we meet on Friday?"
    assert_selector "[data-compose-target='saveStatus']", text: "Saved", wait: 10
    draft = @account.messages.drafts.find_by!(subject: "Plans")

    happened = Queue.new
    hanging_save = Module.new do
      define_method(:update) do
        return super() unless params[:autosave]

        happened << :save_started
        sleep 6
        # It finds its draft sent and is refused (RecordNotFound)
        begin
          super()
        ensure
          happened << :save_done
        end
      end
    end
    sent = ->(*, payload) { happened << :send if payload[:controller] == "Tools::MailsController" && payload[:action] == "create" }
    Tools::Mails::DraftsController.prepend(hanging_save)

    ActiveSupport::Notifications.subscribed(sent, "start_processing.action_controller") do
      write " Or Saturday."
      assert_equal :save_started, happened.pop(timeout: 10)
      deliveries = capture_smtp_deliveries do
        perform_enqueued_jobs(only: SendMailJob) do
          click_on "Send"
          assert_selector ".mail-detail-header h1", text: "Plans", wait: 15
        end
      end

      # Sent while the save was still on its way, with what the form held
      assert_equal [ :send, :save_done ], Array.new(2) { happened.pop(timeout: 15) }
      assert_match "Or Saturday.", deliveries.sole[:message]
    end
    assert_not draft.reload.draft?
    assert_match "Or Saturday.", draft.body_html
  ensure
    hanging_save&.remove_method(:update)
  end

  test "Send pressed while the first save hangs goes out without it, and the draft that save makes is deleted" do
    compose
    add_recipient "friend@example.com"
    find("input[name='subject']").set("Plans")

    happened = Queue.new
    hanging_save = Module.new do
      define_method(:create) do
        return super() unless params[:autosave]

        happened << :save_started
        sleep 6
        super().tap { happened << :save_done }
      end
    end
    sent = ->(*, payload) { happened << :send if payload[:controller] == "Tools::MailsController" && payload[:action] == "create" }
    Tools::Mails::DraftsController.prepend(hanging_save)

    ActiveSupport::Notifications.subscribed(sent, "start_processing.action_controller") do
      write "Shall we meet on Friday?"
      assert_equal :save_started, happened.pop(timeout: 10)
      deliveries = capture_smtp_deliveries do
        perform_enqueued_jobs(only: SendMailJob) do
          click_on "Send"
          assert_selector ".mail-detail-header h1", text: "Plans", wait: 15
        end
      end
      assert_match "Shall we meet on Friday?", deliveries.sole[:message]

      assert_equal [ :send, :save_done ], Array.new(2) { happened.pop(timeout: 15) }
    end
    assert_db_change(-> { !@account.messages.drafts.exists?(subject: "Plans") }, timeout: 10)
    assert_equal 1, @account.messages.where(subject: "Plans").count
  ensure
    hanging_save&.remove_method(:create)
  end

  test "discarded while its first save is on its way, the draft that save makes is deleted" do
    compose
    happened = Queue.new
    slow_save = Module.new do
      define_method(:create) do
        happened << :save_started
        sleep 1.5
        super().tap { happened << :save_done }
      end
    end
    Tools::Mails::DraftsController.prepend(slow_save)

    find("input[name='subject']").set("Plans")
    write "Never mind"
    assert_equal :save_started, happened.pop(timeout: 10)
    click_on "Discard"
    assert_equal :save_done, happened.pop(timeout: 10)

    assert_db_change(-> { !@account.messages.drafts.exists?(subject: "Plans") }, timeout: 10)
  ensure
    slow_save&.remove_method(:create)
  end

  test "a reply nobody wrote in saves nothing" do
    visit new_tool_mail_path(@tool, reply_to: mails_messages(:inbox_read).id)
    wait_for_compose_editor
    use_autosave
    find("rhino-editor [contenteditable]").click

    sleep 4
    assert_no_selector "[data-compose-target='saveStatus']", text: "Sav"
    assert_not @account.messages.drafts.exists?(in_reply_to: mails_messages(:inbox_read).message_id)
  end

  test "a forward's files go onto the draft it saves itself as, once, and come off it when taken off" do
    message = mails_messages(:inbox_read)
    %w[keep.pdf drop.pdf].each do |name|
      message.attachments.create!(filename: name, content_type: "application/pdf", file_size: 6)
        .file.attach(io: StringIO.new("%PDF-1"), filename: name, content_type: "application/pdf")
    end
    visit new_tool_mail_path(@tool, forward: message.id)
    wait_for_compose_editor
    use_autosave
    add_recipient "friend@example.com"
    write "FYI"
    assert_selector "[data-compose-target='saveStatus']", text: "Saved", wait: 10
    draft = @account.messages.drafts.order(:created_at).last
    assert_equal %w[drop.pdf keep.pdf], draft.attachments.map(&:filename).sort

    click_on "Remove drop.pdf"
    assert_db_change(-> { draft.reload.attachments.map(&:filename) == %w[keep.pdf] }, timeout: 10)

    deliveries = capture_smtp_deliveries do
      perform_enqueued_jobs(only: SendMailJob) do
        click_on "Send"
        assert_selector ".mail-detail-header"
      end
    end
    assert_equal 1, deliveries.size
    assert_equal %w[keep.pdf], draft.reload.attachments.map(&:filename)
  end

  test "a draft deleted elsewhere stops saving and says so" do
    compose
    find("input[name='subject']").set("Plans")
    write "Shall we meet on Friday?"
    assert_selector "[data-compose-target='saveStatus']", text: "Saved", wait: 10

    @account.discard(@account.messages.drafts.find_by!(subject: "Plans"))
    write " Or Saturday."

    assert_text "This draft was sent or deleted elsewhere", wait: 10
    assert_no_selector "[data-compose-target='saveStatus']", text: "Not saved"
  end

  private

  def compose
    visit new_tool_mail_path(@tool)
    wait_for_compose_editor
    use_autosave
  end

  # The few seconds it waits outside the tests (config/environments/test.rb)
  def use_autosave(ms = 3000)
    execute_script("document.querySelector('form[data-controller~=compose]').dataset.composeAutosaveDelayValue = '#{ms}'")
  end

  # So that what is typed next is still unsaved when the test leaves
  def slow_down_autosave
    use_autosave(60_000)
  end

  def write(text)
    find("rhino-editor [contenteditable]").send_keys(text)
  end

  def add_recipient(address)
    find("input[data-compose-target='to']").set(address).send_keys(:enter)
  end

  def wait_for_compose_editor
    wait_for_stimulus "compose"
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "The editor hasn't started" unless evaluate_script("document.querySelector('rhino-editor').hasInitialized")
    end
    page.evaluate_async_script("requestAnimationFrame(() => requestAnimationFrame(arguments[0]))")
  end
end
