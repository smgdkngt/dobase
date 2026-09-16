# frozen_string_literal: true

require "test_helper"
require "webmock/minitest"

class DeleteCalendarEventJobTest < ActiveJob::TestCase
  setup do
    WebMock.disable_net_connect!
    @event = calendars_events(:meeting)
    @event_data = { remote_href: @event.remote_href, etag: @event.etag, calendar_id: @event.calendar_id, uid: @event.uid }
  end

  teardown do
    WebMock.allow_net_connect!
  end

  test "deletes the event on the CalDAV server" do
    deletion = stub_request(:delete, @event.remote_href)
      .with(headers: { "If-Match" => %("#{@event.etag}") })
      .to_return(status: 204)

    perform_enqueued_jobs { DeleteCalendarEventJob.perform_later(@event_data) }

    assert_requested deletion
  end

  test "finds an event the server hasn't answered for yet by its UID" do
    deletion = stub_request(:delete, "#{calendars_calendars(:personal).remote_url}#{@event.uid}.ics").to_return(status: 404)

    DeleteCalendarEventJob.perform_now(@event_data.merge(remote_href: nil, etag: nil))

    assert_requested deletion
  end

  test "tries again when the server can't be reached or fails" do
    stub_request(:delete, @event.remote_href).to_timeout.then.to_return(status: 503)

    2.times do
      assert_enqueued_with(job: DeleteCalendarEventJob) { DeleteCalendarEventJob.perform_now(@event_data) }
    end
  end

  test "doesn't try again when the server refuses" do
    stub_request(:delete, @event.remote_href).to_return(status: 412)

    DeleteCalendarEventJob.perform_now(@event_data)

    assert_no_enqueued_jobs
  end

  test "leaves events of local calendars alone" do
    tool = Tool.create!(name: "Local Calendar", tool_type: tool_types(:calendar), owner: users(:one))
    local = Calendars::Account.create!(tool: tool, provider: "local").calendars.create!(name: "Local")

    assert_nothing_raised { DeleteCalendarEventJob.perform_now(@event_data.merge(calendar_id: local.id)) }
  end
end
