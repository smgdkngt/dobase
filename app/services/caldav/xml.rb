# frozen_string_literal: true

require "nokogiri"

# The XML bodies Dobase sends to a CalDAV server, and the one way it reads XML back.
module Caldav
  module Xml
    module_function

  def ctag
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <d:propfind xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/">
        <d:prop>
          <cs:getctag/>
        </d:prop>
      </d:propfind>
    XML
  end

  def current_user_principal
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <d:propfind xmlns:d="DAV:">
        <d:prop>
          <d:current-user-principal/>
        </d:prop>
      </d:propfind>
    XML
  end

  def calendar_home_set
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
        <d:prop>
          <c:calendar-home-set/>
        </d:prop>
      </d:propfind>
    XML
  end

  def calendars
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

  def calendar_proppatch(calendar)
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

  def sync_token
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

  def calendar_query
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

  def sync_collection(sync_token)
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

  def parse(body)
    # Responses come from a server the user chose. Never substitute entities: with
    # `noent`, a <!ENTITY x SYSTEM "file:///..."> would read files off this machine.
    Nokogiri::XML(body) { |config| config.nonet }
  end
  end
end
