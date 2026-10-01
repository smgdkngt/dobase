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

  test "moves an event that changed calendars on the server too" do
    old_href = @event.remote_href
    work = calendars_calendars(:work)
    @event.update!(calendar: work)
    created = stub_request(:put, "#{work.remote_url}#{@event.uid}.ics").to_return(status: 201)
    deleted = stub_request(:delete, old_href).to_return(status: 204)

    PushEventJob.perform_now(@event.id, :move)

    assert_requested created
    assert_requested deleted
  end

  test "a change the server turns down for the password shows on the account" do
    stub_request(:put, @event.remote_href).to_return(status: 401)

    assert_nothing_raised { PushEventJob.perform_now(@event.id, :update) }

    assert @event.calendar.account.reload.authentication_failed?
    assert_not @event.calendar.reload.read_only?
    assert_no_enqueued_jobs
  end

  test "marks the calendar read-only when the server refuses a change and says the user can't make any" do
    stub_request(:put, @event.remote_href).to_return(status: 403)
    stub_request(:propfind, @event.calendar.remote_url).to_return(status: 207, body: privileges_response(%w[read]))

    PushEventJob.perform_now(@event.id, :update)

    assert @event.calendar.reload.read_only?
    assert_no_enqueued_jobs
  end

  test "one refused event doesn't make a calendar read-only that the server says the user can change" do
    stub_request(:put, @event.remote_href).to_return(status: 403)
    stub_request(:propfind, @event.calendar.remote_url).to_return(status: 207, body: privileges_response(%w[read write write-content bind]))

    PushEventJob.perform_now(@event.id, :update)

    assert_not @event.calendar.reload.read_only?
  end

  test "when the server doesn't say, a refused event of the user's own makes the calendar read-only, one they only attend doesn't" do
    stub_request(:put, @event.remote_href).to_return(status: 403)
    stub_request(:propfind, @event.calendar.remote_url).to_return(status: 207, body: privileges_response(nil))

    @event.update!(organizer_email: "rachel@example.com", organizer_name: "Rachel Kim")
    PushEventJob.perform_now(@event.id, :update)
    assert_not @event.calendar.reload.read_only?

    @event.update!(organizer_email: @event.calendar.account.username.upcase)
    PushEventJob.perform_now(@event.id, :update)
    assert @event.calendar.reload.read_only?
  end

  private

  def privileges_response(privileges)
    privilege_set = privileges&.map { |privilege| "<d:privilege><d:#{privilege}/></d:privilege>" }&.join
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <d:multistatus xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/">
        <d:response>
          <d:href>/123456789/calendars/personal/</d:href>
          <d:propstat>
            <d:prop>
              <cs:getctag>abc123</cs:getctag>
              #{"<d:current-user-privilege-set>#{privilege_set}</d:current-user-privilege-set>" if privileges}
            </d:prop>
            <d:status>HTTP/1.1 200 OK</d:status>
          </d:propstat>
          #{'<d:propstat><d:prop><d:current-user-privilege-set/></d:prop><d:status>HTTP/1.1 404 Not Found</d:status></d:propstat>' unless privileges}
        </d:response>
      </d:multistatus>
    XML
  end
end
