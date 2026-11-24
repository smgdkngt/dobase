# frozen_string_literal: true

module Mails
  # The mail services the setup form fills in the servers for (mail_provider_controller.js).
  # Hosts and ports are the ones each service documents; SMTP goes over 587 with STARTTLS
  # everywhere, since that is what SmtpSendService speaks (smtp_tls). Each needs an app
  # password: their sign-in with a browser (OAuth) is nothing Dobase does.
  module Provider
    ALL = {
      "gmail" => {
        name: "Gmail", domains: %w[gmail.com googlemail.com],
        imap_host: "imap.gmail.com", imap_port: 993, imap_ssl: true,
        smtp_host: "smtp.gmail.com", smtp_port: 587, smtp_tls: true, smtp_auth: "plain",
        app_password_url: "https://myaccount.google.com/apppasswords",
        hint: "Gmail wants an app password, which needs 2-Step Verification on your Google account."
      },
      "icloud" => {
        name: "iCloud", domains: %w[icloud.com me.com mac.com],
        imap_host: "imap.mail.me.com", imap_port: 993, imap_ssl: true,
        smtp_host: "smtp.mail.me.com", smtp_port: 587, smtp_tls: true, smtp_auth: "plain",
        app_password_url: "https://support.apple.com/en-us/102654",
        hint: "iCloud wants an app-specific password, made under Sign-In and Security at account.apple.com."
      },
      "fastmail" => {
        name: "Fastmail", domains: %w[fastmail.com fastmail.fm],
        imap_host: "imap.fastmail.com", imap_port: 993, imap_ssl: true,
        smtp_host: "smtp.fastmail.com", smtp_port: 587, smtp_tls: true, smtp_auth: "plain",
        app_password_url: "https://www.fastmail.help/hc/en-us/articles/360058752854-App-passwords",
        hint: "Fastmail wants an app password with IMAP and SMTP access. Basic plans can't use other mail programs."
      },
      "outlook" => {
        name: "Outlook", domains: %w[outlook.com hotmail.com live.com msn.com],
        imap_host: "outlook.office365.com", imap_port: 993, imap_ssl: true,
        smtp_host: "smtp-mail.outlook.com", smtp_port: 587, smtp_tls: true, smtp_auth: "login",
        app_password_url: "https://support.microsoft.com/en-us/office/pop-imap-and-smtp-settings-for-outlook-com-d088b986-291d-42b8-9564-9c414e2aa040",
        hint: "Microsoft turns most password logins down and asks for a sign-in Dobase can't do yet. An app password works where Microsoft still allows one."
      },
      "other" => { name: "Other" }
    }.freeze

    # What the form's script needs: the servers to fill in and where the app password is made
    def self.presets
      ALL.transform_values do |provider|
        provider.except(:name).merge(provider.slice(:hint).transform_values { |hint| Translation.translate(hint) })
      end
    end
  end
end
