# frozen_string_literal: true

require "net/http"
require "nokogiri"
require "ostruct"
require "cgi"
require "icalendar"

class CaldavSyncService
  class ConnectionError < StandardError; end
  class AuthenticationError < StandardError; end
  class SyncError < StandardError; end

  # Custom HTTP request classes for WebDAV methods
  class Propfind < Net::HTTPRequest
    METHOD = "PROPFIND"
    REQUEST_HAS_BODY = true
    RESPONSE_HAS_BODY = true
  end

  class Report < Net::HTTPRequest
    METHOD = "REPORT"
    REQUEST_HAS_BODY = true
    RESPONSE_HAS_BODY = true
  end

  class Proppatch < Net::HTTPRequest
    METHOD = "PROPPATCH"
    REQUEST_HAS_BODY = true
    RESPONSE_HAS_BODY = true
  end

  PROVIDER_PRESETS = {
    "fastmail" => {
      base_url: "https://caldav.fastmail.com",
      principal_path: "/dav/principals/user/%{username}/"
    },
    "icloud" => {
      base_url: "https://caldav.icloud.com",
      principal_path: "/%{username}/"
    },
    "nextcloud" => {
      base_url: nil, # User must provide
      principal_path: "/remote.php/dav/principals/users/%{username}/"
    },
    "google" => {
      base_url: "https://apidata.googleusercontent.com",
      principal_path: "/caldav/v2/%{username}/"
    }
  }.freeze

  DAV_NAMESPACE = { "d" => "DAV:", "c" => "urn:ietf:params:xml:ns:caldav", "cs" => "http://calendarserver.org/ns/" }.freeze

  def initialize(calendar_account)
    @account = calendar_account
  end

  def test_connection
    return true if @account.local?

    response = propfind(@account.caldav_url, depth: 0, body: propfind_current_user_principal_xml)
    raise AuthenticationError, "Authentication failed" if response.status == 401
    raise ConnectionError, "Connection failed: #{response.status}" unless response.success?
    true
  rescue Faraday::Error => e
    raise ConnectionError, "Connection failed: #{e.message}"
  end

  def discover_calendars
    return if @account.local?
    principal_url = discover_principal_url
    raise SyncError, "Could not discover principal URL" unless principal_url

    calendar_home_url = discover_calendar_home(principal_url)
    raise SyncError, "Could not discover calendar home" unless calendar_home_url

    calendars = list_calendars(calendar_home_url)
    save_discovered_calendars(calendars)
  end

  def sync_all_calendars
    return if @account.local?

    @account.calendars.enabled.find_each do |calendar|
      sync_calendar(calendar)
    rescue SyncError => e
      Rails.logger.warn("Skipping calendar #{calendar.name} (#{calendar.id}): #{e.message}")
    end
  end

  def sync_calendar(calendar)
    return if @account.local?
    if calendar.sync_token.present? && !ctag_changed?(calendar)
      delta_sync(calendar)
    else
      full_sync(calendar)
    end
  end

  def ctag_changed?(calendar)
    return true unless calendar.ctag.present?

    response = propfind(calendar.remote_url, depth: 0, body: propfind_ctag_xml)
    return true unless response.success?

    doc = parse_xml(response.body)
    server_ctag = doc.at_xpath("//*[local-name()='getctag']")&.text

    calendar.ctag != server_ctag
  end

  def propfind_ctag_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <d:propfind xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/">
        <d:prop>
          <cs:getctag/>
        </d:prop>
      </d:propfind>
    XML
  end

  def create_event(event)
    return if event.calendar.local?

    calendar = event.calendar
    ics_data = build_icalendar(event)
    url = "#{calendar.remote_url}#{event.uid}.ics"

    response = http_client.put(url) do |req|
      req.headers["Content-Type"] = "text/calendar; charset=utf-8"
      req.body = ics_data
    end

    raise SyncError, "Failed to create event: #{response.status}" unless response.success?

    event.update!(
      etag: response.headers["etag"]&.gsub('"', ""),
      remote_href: url
    )
  end

  def update_event(event)
    return if event.calendar.local?

    url = event.remote_href.presence || "#{event.calendar.remote_url}#{event.uid}.ics"
    ics_data = build_icalendar(event)

    response = http_client.put(url) do |req|
      req.headers["Content-Type"] = "text/calendar; charset=utf-8"
      req.headers["If-Match"] = %("#{event.etag}") if event.etag.present?
      req.body = ics_data
    end

    raise SyncError, "Failed to update event: #{response.status}" unless response.success?

    event.update!(etag: response.headers["etag"]&.gsub('"', ""))
  end

  def delete_event(event)
    return if event.calendar.local?
    return unless event.remote_href.present?

    response = http_client.delete(event.remote_href) do |req|
      req.headers["If-Match"] = %("#{event.etag}") if event.etag.present?
    end

    # 204 No Content or 404 Not Found are both acceptable
    unless response.success? || response.status == 404
      raise SyncError, "Failed to delete event: #{response.status}"
    end
  end

  def update_calendar(calendar)
    return if calendar.local?
    return unless calendar.remote_url.present?

    response = proppatch(calendar.remote_url, calendar_proppatch_xml(calendar))

    unless response.success?
      raise SyncError, "Failed to update calendar: #{response.status}"
    end
  end

  private

  def http_client
    @http_client ||= Faraday.new do |f|
      f.request :authorization, :basic, @account.username, @account.password
      f.options.timeout = 30
      f.options.open_timeout = 10
      f.adapter Faraday.default_adapter
    end
  end

  def propfind(url, depth: 0, body: nil)
    make_webdav_request("PROPFIND", url, body, { "Depth" => depth.to_s })
  end

  def report(url, body)
    make_webdav_request("REPORT", url, body, { "Depth" => "1" })
  end

  def proppatch(url, body)
    make_webdav_request("PROPPATCH", url, body)
  end

  def make_webdav_request(method, url, body, extra_headers = {})
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    if uri.scheme == "https"
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.cert_store = OpenSSL::X509::Store.new
      http.cert_store.set_default_paths
    end
    http.open_timeout = 10
    http.read_timeout = 30

    request_class = case method.upcase
    when "PROPFIND" then Propfind
    when "REPORT" then Report
    when "PROPPATCH" then Proppatch
    else raise ArgumentError, "Unsupported WebDAV method: #{method}"
    end

    request = request_class.new(uri.request_uri)
    request.basic_auth(@account.username, @account.password)
    request["Content-Type"] = "application/xml; charset=utf-8"
    extra_headers.each { |k, v| request[k] = v }
    request.body = body if body

    response = http.request(request)

    # Wrap in a simple struct to match interface
    OpenStruct.new(
      status: response.code.to_i,
      body: response.body,
      success?: response.is_a?(Net::HTTPSuccess),
      headers: response.to_hash
    )
  end

  def discover_principal_url
    response = propfind(@account.caldav_url, depth: 0, body: propfind_current_user_principal_xml)
    return nil unless response.success?

    doc = parse_xml(response.body)
    # Use local-name() to handle default namespaces without prefixes
    href = doc.at_xpath("//*[local-name()='current-user-principal']/*[local-name()='href']")&.text
    return nil unless href

    resolve_url(href)
  end

  def discover_calendar_home(principal_url)
    response = propfind(principal_url, depth: 0, body: propfind_calendar_home_set_xml)
    return nil unless response.success?

    doc = parse_xml(response.body)
    href = doc.at_xpath("//*[local-name()='calendar-home-set']/*[local-name()='href']")&.text
    return nil unless href

    resolve_url(href)
  end

  def list_calendars(calendar_home_url)
    response = propfind(calendar_home_url, depth: 1, body: propfind_calendars_xml)
    return [] unless response.success?

    doc = parse_xml(response.body)
    calendars = []

    doc.xpath("//*[local-name()='response']").each do |resp|
      href = resp.at_xpath("*[local-name()='href']")&.text
      next unless href

      # Check if it's a calendar (has calendar component)
      resource_types = resp.xpath(".//*[local-name()='resourcetype']/*").map(&:name)
      next unless resource_types.include?("calendar")

      displayname = resp.at_xpath(".//*[local-name()='displayname']")&.text
      color = resp.at_xpath(".//*[local-name()='calendar-color']")&.text
      ctag = resp.at_xpath(".//*[local-name()='getctag']")&.text
      sync_token = resp.at_xpath(".//*[local-name()='sync-token']")&.text

      resolved_url = resolve_url(href)
      calendars << {
        remote_id: href,
        remote_url: resolved_url,
        name: displayname || File.basename(href),
        color: normalize_color(color),
        ctag: ctag,
        sync_token: sync_token,
        read_only: !calendar_writable?(resolved_url)
      }
    end

    calendars
  end

  def save_discovered_calendars(calendars)
    calendars.each_with_index do |cal_data, index|
      calendar = @account.calendars.find_or_initialize_by(remote_id: cal_data[:remote_id])
      is_new = calendar.new_record?

      # For existing calendars, preserve ctag and sync_token so ctag_changed? works correctly
      calendar.assign_attributes(
        remote_url: cal_data[:remote_url],
        name: is_new ? cal_data[:name] : calendar.name,
        color: is_new ? cal_data[:color] : calendar.color,
        ctag: is_new ? cal_data[:ctag] : calendar.ctag,
        sync_token: is_new ? cal_data[:sync_token] : calendar.sync_token,
        position: is_new ? index : calendar.position,
        enabled: is_new ? true : calendar.enabled,
        is_default: is_new && index == 0,
        read_only: cal_data.fetch(:read_only, false)
      )
      calendar.save!
    end
  end

  def full_sync(calendar)
    response = report(calendar.remote_url, calendar_query_xml)

    if response.status == 404
      calendar.update!(enabled: false)
      Rails.logger.info("Calendar '#{calendar.name}' no longer exists on server, disabled.")
      return
    end

    raise SyncError, "Full sync failed: #{response.status}" unless response.success?

    doc = parse_xml(response.body)
    events_data = parse_calendar_data_response(doc)

    # Mark all existing events for potential deletion
    existing_uids = calendar.events.pluck(:uid)
    synced_uids = []

    events_data.each do |event_data|
      save_event(calendar, event_data)
      synced_uids << event_data[:uid]
    end

    # Remove events that no longer exist on server
    removed_uids = existing_uids - synced_uids
    calendar.events.where(uid: removed_uids).destroy_all if removed_uids.any?

    # Update sync token
    update_calendar_sync_token(calendar)
  end

  def delta_sync(calendar)
    response = report(calendar.remote_url, sync_collection_xml(calendar.sync_token))

    # If sync-token is invalid, fall back to full sync
    if response.status == 403 || response.status == 412
      calendar.update!(sync_token: nil)
      return full_sync(calendar)
    end

    raise SyncError, "Delta sync failed: #{response.status}" unless response.success?

    doc = parse_xml(response.body)

    # Process changed/new events
    doc.xpath("//*[local-name()='response']").each do |resp|
      href = resp.at_xpath("*[local-name()='href']")&.text
      status = resp.at_xpath(".//*[local-name()='status']")&.text

      if status&.include?("404")
        # Event was deleted
        uid = extract_uid_from_href(href)
        calendar.events.where(uid: uid).destroy_all if uid
      else
        # Event was created or updated
        calendar_data = resp.at_xpath(".//*[local-name()='calendar-data']")&.text
        etag = resp.at_xpath(".//*[local-name()='getetag']")&.text&.gsub('"', "")

        if calendar_data.present?
          parsed = IcsParserService.new(calendar_data).parse
          if parsed[:uid].present?
            save_event(calendar, parsed.merge(etag: etag, remote_url: resolve_url(href)))
          end
        end
      end
    end

    # Update sync token
    new_sync_token = doc.at_xpath("//*[local-name()='sync-token']")&.text
    calendar.update!(sync_token: new_sync_token) if new_sync_token.present?

    # TODO: Some CalDAV servers (like iCloud) don't report deletions in sync-collection
    # For now, skip verification as it's too slow with many events
    # verify_events_exist(calendar)
  end

  def verify_events_exist(calendar)
    # Only verify events created locally (pushed to server) - they have @app_name in UID
    # Events synced from server are authoritative and don't need verification
    uid_suffix = Rails.application.config.x.app.name.parameterize
    calendar.events.where("uid LIKE ?", "%@#{uid_suffix}").where.not(remote_href: nil).find_each do |event|
      response = http_client.head(event.remote_href)
      if response.status == 404
        Rails.logger.info("Event #{event.uid} no longer exists on server, deleting locally")
        event.destroy
      end
    end
  rescue StandardError => e
    # Don't fail the sync if verification fails
    Rails.logger.warn("Event verification failed: #{e.message}")
  end

  def parse_calendar_data_response(doc)
    events = []

    # Use local-name() to handle default namespaces without prefixes (e.g., iCloud)
    doc.xpath("//*[local-name()='response']").each do |resp|
      href = resp.at_xpath("*[local-name()='href']")&.text
      calendar_data = resp.at_xpath(".//*[local-name()='calendar-data']")&.text
      etag = resp.at_xpath(".//*[local-name()='getetag']")&.text&.gsub('"', "")

      next unless calendar_data.present?

      parsed = IcsParserService.new(calendar_data).parse
      next unless parsed[:uid].present?

      events << parsed.merge(etag: etag, remote_url: resolve_url(href))
    end

    events
  end

  def save_event(calendar, event_data)
    event = calendar.events.find_or_initialize_by(uid: event_data[:uid])

    event.assign_attributes(
      summary: event_data[:summary],
      description: event_data[:description],
      location: event_data[:location],
      starts_at: event_data[:starts_at],
      ends_at: event_data[:ends_at],
      all_day: event_data[:all_day] || false,
      status: event_data[:status],
      organizer_email: event_data[:organizer_email],
      organizer_name: event_data[:organizer_name],
      attendees: event_data[:attendees] || [],
      is_recurring: event_data[:rrule].present?,
      rrule: event_data[:rrule],
      recurrence_schedule: event_data[:recurrence_schedule],
      etag: event_data[:etag],
      remote_href: event_data[:remote_url],
      raw_icalendar: event_data[:raw_icalendar]
    )

    event.save!
    event
  end

  def update_calendar_sync_token(calendar)
    response = propfind(calendar.remote_url, depth: 0, body: propfind_sync_token_xml)
    return unless response.success?

    doc = parse_xml(response.body)
    sync_token = doc.at_xpath("//*[local-name()='sync-token']")&.text
    ctag = doc.at_xpath("//*[local-name()='getctag']")&.text

    calendar.update!(sync_token: sync_token, ctag: ctag)
  end

  def calendar_writable?(calendar_url)
    test_uid = SecureRandom.uuid.upcase
    url = "#{calendar_url}#{test_uid}.ics"
    body = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//WriteTest//EN\r\nBEGIN:VEVENT\r\nUID:#{test_uid}\r\nDTSTAMP:#{Time.current.utc.strftime('%Y%m%dT%H%M%SZ')}\r\nDTSTART:#{1.day.from_now.utc.strftime('%Y%m%dT%H%M%SZ')}\r\nDTEND:#{(1.day.from_now + 1.hour).utc.strftime('%Y%m%dT%H%M%SZ')}\r\nSUMMARY:Write test\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

    response = http_client.put(url) do |req|
      req.headers["Content-Type"] = "text/calendar; charset=utf-8"
      req.body = body
    end

    if response.success?
      http_client.delete(url) rescue nil
      true
    else
      false
    end
  rescue
    false
  end

  def build_icalendar(event)
    cal = Icalendar::Calendar.new
    cal.prodid = "-//#{Rails.application.config.x.app.name}//Calendar//EN"

    vevent = Icalendar::Event.new
    vevent.uid = event.uid
    vevent.summary = event.summary
    vevent.description = event.description if event.description.present?
    vevent.location = event.location if event.location.present?

    if event.all_day?
      vevent.dtstart = Icalendar::Values::Date.new(event.starts_at.to_date)
      vevent.dtend = Icalendar::Values::Date.new(event.ends_at.to_date)
    else
      vevent.dtstart = Icalendar::Values::DateTime.new(event.starts_at.utc)
      vevent.dtend = Icalendar::Values::DateTime.new(event.ends_at.utc)
    end

    vevent.status = event.status.upcase if event.status.present?

    if event.is_recurring? && event.rrule.present?
      vevent.rrule = [ Icalendar::Values::Recur.new(event.rrule) ]
    end

    if event.organizer_email.present?
      organizer = Icalendar::Values::CalAddress.new("mailto:#{event.organizer_email}")
      organizer.cn = event.organizer_name if event.organizer_name.present?
      vevent.organizer = organizer
    end

    event.attendees.each do |attendee|
      addr = Icalendar::Values::CalAddress.new("mailto:#{attendee['email']}")
      addr.cn = attendee["name"] if attendee["name"].present?
      addr.partstat = attendee["status"]&.upcase || "NEEDS-ACTION"
      vevent.append_attendee(addr)
    end

    vevent.dtstamp = Icalendar::Values::DateTime.new(Time.current.utc)

    cal.add_event(vevent)
    cal.publish
    cal.to_ical
  end

  def resolve_url(href)
    return href if href.start_with?("http")
    uri = URI.parse(@account.caldav_url)
    "#{uri.scheme}://#{uri.host}#{href}"
  end

  def normalize_color(color)
    return nil unless color.present?
    # Remove alpha channel if present (e.g., #FF5500FF -> #FF5500)
    color.gsub(/^(#[0-9A-Fa-f]{6})[0-9A-Fa-f]{2}$/, '\1')
  end

  def extract_uid_from_href(href)
    return nil unless href
    # Extract UID from path like /calendars/user/calendar/event-uid.ics
    match = href.match(/([^\/]+)\.ics$/)
    return nil unless match
    # URL-decode the UID (e.g., %40 -> @)
    CGI.unescape(match[1])
  end

  # XML request bodies

  def propfind_current_user_principal_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <d:propfind xmlns:d="DAV:">
        <d:prop>
          <d:current-user-principal/>
        </d:prop>
      </d:propfind>
    XML
  end

  def propfind_calendar_home_set_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
        <d:prop>
          <c:calendar-home-set/>
        </d:prop>
      </d:propfind>
    XML
  end

  def propfind_calendars_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/" xmlns:x="http://apple.com/ns/ical/">
        <d:prop>
          <d:resourcetype/>
          <d:displayname/>
          <x:calendar-color/>
          <cs:getctag/>
          <d:sync-token/>
        </d:prop>
      </d:propfind>
    XML
  end

  def calendar_proppatch_xml(calendar)
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <d:propertyupdate xmlns:d="DAV:" xmlns:x="http://apple.com/ns/ical/">
        <d:set>
          <d:prop>
            <d:displayname>#{ERB::Util.html_escape(calendar.name)}</d:displayname>
            <x:calendar-color>#{calendar.color_hex}FF</x:calendar-color>
          </d:prop>
        </d:set>
      </d:propertyupdate>
    XML
  end

  def propfind_sync_token_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <d:propfind xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/">
        <d:prop>
          <d:sync-token/>
          <cs:getctag/>
        </d:prop>
      </d:propfind>
    XML
  end

  def calendar_query_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
        <d:prop>
          <d:getetag/>
          <c:calendar-data/>
        </d:prop>
        <c:filter>
          <c:comp-filter name="VCALENDAR">
            <c:comp-filter name="VEVENT"/>
          </c:comp-filter>
        </c:filter>
      </c:calendar-query>
    XML
  end

  def parse_xml(body)
    Nokogiri::XML(body) { |config| config.nonet.noent }
  end

  def sync_collection_xml(sync_token)
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <d:sync-collection xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
        <d:sync-token>#{ERB::Util.html_escape(sync_token)}</d:sync-token>
        <d:sync-level>1</d:sync-level>
        <d:prop>
          <d:getetag/>
          <c:calendar-data/>
        </d:prop>
      </d:sync-collection>
    XML
  end
end
