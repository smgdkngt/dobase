# frozen_string_literal: true

module Mails
  # Logs in to an account's IMAP and SMTP servers before the account is saved, so a wrong
  # password or server is said on the form instead of after a sync that found nothing.
  # It connects the way the sync and sending do (ImapSyncService, SmtpSendService), with
  # RemoteHost's check of the host, and gives up after TIMEOUT per server: someone waits.
  class ConnectionCheck
    TIMEOUT = 10

    # What changing makes the login worth trying again
    SETTINGS = %w[imap_host imap_port imap_ssl smtp_host smtp_port smtp_auth smtp_tls username encrypted_password].freeze

    def initialize(account)
      @account = account
    end

    # Nil when both servers took the login, else what went wrong, in words
    def problem
      imap_problem || smtp_problem
    end

    private

    def imap_problem
      within_time { ImapSyncService.new(@account).check_login(timeout: TIMEOUT) }
      nil
    rescue StandardError => error
      "Incoming mail (#{@account.imap_host}): #{ConnectionProblem.in_words(error.message)}"
    end

    def smtp_problem
      within_time { SmtpSendService.new(@account).check_login(timeout: TIMEOUT) }
      nil
    rescue StandardError => error
      "Outgoing mail (#{@account.smtp_host}): #{ConnectionProblem.in_words(error.message)}"
    end

    # A server that takes the connection and then says nothing would keep the request waiting
    def within_time(&block)
      Timeout.timeout(TIMEOUT + 2, Timeout::Error, "execution expired", &block)
    end
  end
end
