# frozen_string_literal: true

require "test_helper"
require "webmock/minitest"

class PushEventJobTest < ActiveJob::TestCase
  setup do
    WebMock.disable_net_connect!
    @event = calendars_events(:meeting)
  end

  teardown do
    WebMock.allow_net_connect!
  end

  test "tries again when the server can't be reached or fails" do
    stub_request(:put, @event.remote_href).to_timeout.then.to_return(status: 502)

    2.times do
      assert_enqueued_with(job: PushEventJob, args: [ @event.id, :update ]) { PushEventJob.perform_now(@event.id, :update) }
    end
  end

  test "marks the calendar read-only when the server refuses changes" do
    stub_request(:put, @event.remote_href).to_return(status: 403)

    PushEventJob.perform_now(@event.id, :update)

    assert @event.calendar.reload.read_only?
    assert_no_enqueued_jobs
  end
end
