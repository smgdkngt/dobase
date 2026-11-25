# frozen_string_literal: true

module Mails
  # What went wrong talking to a mail server, in words someone who set up the account
  # can act on. The sync keeps only an error's message (`sync_error`), so the words are
  # read off that; a check that has the error itself (ConnectionCheck) passes its message.
  module ConnectionProblem
    module_function

    # A sentence that starts in lower case and ends with a full stop, to follow "Not updated since 9:41: "
    def in_words(message)
      message = message.to_s.squish
      case message
      when Mails::Account::AUTHENTICATION_FAILED, /authenticat|invalid credentials|username and password|535|534 /i
        Translation.translate("the mail server didn't accept the username or password.")
      when /(\S+) could not be (found|looked up)/
        Translation.translate("%{host} could not be found. Check the server name.", host: $1)
      when /getaddrinfo|name or service not known|nodename nor servname/i
        Translation.translate("the server could not be found. Check the server name.")
      when /a local address|a private network|from the demo/ then lowercase_first(message)
      when /execution expired|timed out|timeout|ETIMEDOUT/i
        Translation.translate("the mail server didn't answer in time.")
      when /connection refused|ECONNREFUSED/i
        Translation.translate("the mail server refused the connection. Check the server name and port.")
      when /unreachable|EHOSTUNREACH|ENETUNREACH|connection reset|end of file|ECONNRESET/i
        Translation.translate("the mail server couldn't be reached. Check the server name, or try again later.")
      when /SSL|certificate|wrong version number/i
        Translation.translate("no secure connection could be made. Check the port and the SSL setting.")
      when "" then Translation.translate("something went wrong syncing.")
      else Translation.translate("the mail server said: %{error}", error: message.truncate(200))
      end
    end

    def lowercase_first(message)
      sentence = message.end_with?(".") ? message : "#{message}."
      sentence.sub(/\A[A-Z](?=[a-z ])/, &:downcase)
    end
  end
end
