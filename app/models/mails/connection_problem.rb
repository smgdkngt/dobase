# frozen_string_literal: true

module Mails
  # What went wrong talking to a mail server, in words someone who set up the account
  # can act on. The sync keeps only an error's message (`sync_error`), so the words are
  # read off that; a check that has the error itself (ConnectionCheck) passes its message.
  module ConnectionProblem
    LOGIN_REFUSED = "the mail server didn't accept the username or password."
    TIMED_OUT = "the mail server didn't answer in time."
    REFUSED = "the mail server refused the connection. Check the server name and port."
    UNREACHABLE = "the mail server couldn't be reached. Check the server name, or try again later."
    NOT_SECURE = "no secure connection could be made. Check the port and the SSL setting."

    module_function

    # A sentence that starts in lower case and ends with a full stop, to follow "Not updated since 9:41: "
    def in_words(message)
      message = message.to_s.squish
      case message
      when Mails::Account::AUTHENTICATION_FAILED, /authenticat|invalid credentials|username and password|535|534 /i then LOGIN_REFUSED
      when /(\S+) could not be (found|looked up)/ then "#{$1} could not be found. Check the server name."
      when /getaddrinfo|name or service not known|nodename nor servname/i then "the server could not be found. Check the server name."
      when /a local address|a private network|from the demo/ then lowercase_first(message)
      when /execution expired|timed out|timeout|ETIMEDOUT/i then TIMED_OUT
      when /connection refused|ECONNREFUSED/i then REFUSED
      when /unreachable|EHOSTUNREACH|ENETUNREACH|connection reset|end of file|ECONNRESET/i then UNREACHABLE
      when /SSL|certificate|wrong version number/i then NOT_SECURE
      when "" then "something went wrong syncing."
      else "the mail server said: #{message.truncate(200)}"
      end
    end

    def lowercase_first(message)
      sentence = message.end_with?(".") ? message : "#{message}."
      sentence.sub(/\A[A-Z](?=[a-z ])/, &:downcase)
    end
  end
end
