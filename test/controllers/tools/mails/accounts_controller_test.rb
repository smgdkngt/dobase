# frozen_string_literal: true

require "test_helper"

module Tools
  module Mails
    class AccountsControllerTest < ActionDispatch::IntegrationTest
      setup do
        sign_in_as users(:one)
        @tool = tools(:my_mail)
        @account = mails_accounts(:primary)
      end

      test "the settings show the mail page's one-minute refresh for an account that never chose one" do
        assert_nil @account.auto_refresh_interval

        get_settings

        assert_select "select[name='mails_account[auto_refresh_interval]'] option[selected]", text: "1 minute"
      end

      test "the settings show Disabled when auto-refresh is off" do
        @account.update!(auto_refresh_interval: 0)

        get_settings

        assert_select "select[name='mails_account[auto_refresh_interval]'] option[selected]", text: "Disabled"
      end

      test "invalid settings show the email settings again with the error" do
        patch tool_mails_account_path(@tool), params: { mails_account: { imap_host: "   ", signature: "Best, Sem" } }

        assert_response :unprocessable_entity
        assert_select "[data-controller='tabs'][data-tabs-default-value='email']" do
          assert_select "[data-tab='email'] .flash-error", text: "IMAP server can't be blank"
          assert_select "textarea[name='mails_account[signature]']", text: "Best, Sem"
        end
        assert_equal "imap.example.com", @account.reload.imap_host
      end

      test "new connection settings sync an account whose login was turned down again" do
        @account.mark_sync_error!(::Mails::Account::AUTHENTICATION_FAILED)

        assert_no_enqueued_jobs only: SyncEmailsJob do
          patch tool_mails_account_path(@tool), params: { mails_account: { signature: "Best, Sem", password: "" } }
        end
        assert @account.reload.authentication_failed?

        assert_enqueued_with job: SyncEmailsJob, args: [ @account.id ] do
          with_mail_servers { patch tool_mails_account_path(@tool), params: { mails_account: { password: "the-right-one" } } }
        end
        assert @account.reload.syncing?
      end

      test "there are no connection test or mail label endpoints" do
        post "/tools/#{@tool.id}/mails/account/test_connection"
        assert_response :not_found

        get "/tools/#{@tool.id}/mail_labels"
        assert_response :not_found
      end

      test "the settings open on the first tab when nothing went wrong" do
        get_settings

        assert_select "[data-controller='tabs'][data-tabs-default-value='settings']"
      end

      test "the labels of the mail settings point at their fields" do
        get_settings

        assert_labels_point_at_fields "[data-tabs-target='panel'][data-tab='email']"
      end

      test "a mail account setup that can't be saved lists every field it outlines" do
        tool = Tool.create!(name: "Support", tool_type: tool_types(:mail), owner: users(:one))
        blank = { email_address: " ", username: " ", password: " ", imap_host: " ", smtp_host: " " }

        post tool_mails_account_path(tool), params: { mails_account: blank }

        assert_response :unprocessable_entity
        assert_equal [ "Email address can't be blank", "IMAP server can't be blank", "SMTP server can't be blank", "Username can't be blank", "Password can't be blank" ],
          css_select(".flash-error li").map { |item| item.text.strip }
        assert_equal %w[mails_account[email_address] mails_account[imap_host] mails_account[password] mails_account[smtp_host] mails_account[username]],
          css_select(".input-error").map { |field| field["name"] }.sort
      end

      test "the labels of the mail account setup point at their fields" do
        tool = Tool.create!(name: "Support", tool_type: tool_types(:mail), owner: users(:one))

        get new_tool_mails_account_path(tool)

        assert_response :success
        assert_labels_point_at_fields "form"
      end

      test "a login the mail server turns down is said on the setup form, and nothing is saved" do
        tool = Tool.create!(name: "Support", tool_type: tool_types(:mail), owner: users(:one))
        imap = FakeImapServer.new(refuses_login: "[AUTHENTICATIONFAILED] Invalid credentials (Failure)")

        assert_no_difference -> { ::Mails::Account.count } do
          assert_no_enqueued_jobs only: SyncEmailsJob do
            with_mail_servers(imap: imap) { post tool_mails_account_path(tool), params: { mails_account: connection } }
          end
        end

        assert_response :unprocessable_entity
        assert_equal [ [ "ann@example.com", "wrong" ] ], imap.tried_logins
        assert_select ".flash-error", text: /Incoming mail \(imap\.example\.com\): the mail server didn't accept the username or password/
        assert_select "input[name='mails_account[email_address]'][value='ann@example.com']"
      end

      test "an outgoing server that turns the login down is said too" do
        tool = Tool.create!(name: "Support", tool_type: tool_types(:mail), owner: users(:one))
        smtp = SmtpTestHelper::FakeSmtp.new(refuses_login: Net::SMTPAuthenticationError.new("535 5.7.8 Username and Password not accepted"))

        assert_no_difference -> { ::Mails::Account.count } do
          with_mail_servers(smtp: smtp) { post tool_mails_account_path(tool), params: { mails_account: connection } }
        end

        assert_response :unprocessable_entity
        assert_select ".flash-error", text: /Outgoing mail \(smtp\.example\.com\): the mail server didn't accept the username or password/
        assert_equal [ 10, 10 ], [ smtp.open_timeout, smtp.read_timeout ]
      end

      test "a server that can't be found, or is on this machine, is said in words without trying to connect" do
        tool = Tool.create!(name: "Support", tool_type: tool_types(:mail), owner: users(:one))
        imap = FakeImapServer.new

        with_mail_servers(imap: imap) { post tool_mails_account_path(tool), params: { mails_account: connection(imap_host: "imap.nowhere.invalid") } }
        assert_response :unprocessable_entity
        assert_select ".flash-error", text: /imap\.nowhere\.invalid could not be found\. Check the server name\./

        with_mail_servers(imap: imap) { post tool_mails_account_path(tool), params: { mails_account: connection(imap_host: "localhost") } }
        assert_response :unprocessable_entity
        assert_select ".flash-error", text: /a local address/
        assert_empty imap.tried_logins
      end

      test "a login both servers take connects the account and syncs it" do
        tool = Tool.create!(name: "Support", tool_type: tool_types(:mail), owner: users(:one))
        imap, smtp = FakeImapServer.new, SmtpTestHelper::FakeSmtp.new

        assert_enqueued_jobs 1, only: SyncEmailsJob do
          with_mail_servers(imap: imap, smtp: smtp) { post tool_mails_account_path(tool), params: { mails_account: connection(password: "right") } }
        end

        assert_redirected_to tool_mails_path(tool)
        assert_equal [ [ "ann@example.com", "right" ] ], imap.tried_logins
        assert_equal [ [ "ann@example.com", "right" ] ], smtp.logins
        assert_equal "imap.example.com", tool.reload.mail_account.imap_host
      end

      test "new credentials the server turns down are said in the email settings, and the old ones stay" do
        imap = FakeImapServer.new(refuses_login: "Invalid credentials")

        with_mail_servers(imap: imap) { patch tool_mails_account_path(@tool), params: { mails_account: { password: "wrong" } } }

        assert_response :unprocessable_entity
        assert_select "[data-controller='tabs'][data-tabs-default-value='email'] [data-tab='email'] .flash-error",
          text: /didn't accept the username or password/
        assert_equal "testpassword", @account.reload.password
      end

      test "settings that don't touch the connection are saved without trying the login" do
        patch tool_mails_account_path(@tool), params: { mails_account: { signature: "Best, Sem", password: "" } }

        assert_redirected_to tool_mails_path(@tool)
        assert_equal "Best, Sem", @account.reload.signature
      end

      test "the setup form offers the providers, each with its servers and where to make an app password" do
        tool = Tool.create!(name: "Support", tool_type: tool_types(:mail), owner: users(:one))

        get new_tool_mails_account_path(tool)

        assert_equal %w[Gmail iCloud Fastmail Outlook Other], css_select("[data-mail-provider-target='choice']").map { |button| button.text.strip }
        presets = JSON.parse(css_select("[data-controller='mail-provider']").first["data-mail-provider-presets-value"])
        assert_equal({ "imap_host" => "imap.mail.me.com", "imap_port" => 993, "imap_ssl" => true, "smtp_host" => "smtp.mail.me.com", "smtp_port" => 587, "smtp_tls" => true, "smtp_auth" => "plain" },
          presets["icloud"].slice("imap_host", "imap_port", "imap_ssl", "smtp_host", "smtp_port", "smtp_tls", "smtp_auth"))
        assert_equal "https://myaccount.google.com/apppasswords", presets["gmail"]["app_password_url"]
      end

      test "cancelling the setup leaves the tool, which would only bring the form back" do
        tool = Tool.create!(name: "Support", tool_type: tool_types(:mail), owner: users(:one))

        get new_tool_mails_account_path(tool)

        assert_select "a[href='#{root_path}']", text: "Cancel"
        assert_select "a[href='#{tool_path(tool)}']", text: "Cancel", count: 0
      end

      private
        def connection(**overrides)
          { email_address: "ann@example.com", username: "ann@example.com", password: "wrong",
            imap_host: "imap.example.com", imap_port: 993, imap_ssl: "1",
            smtp_host: "smtp.example.com", smtp_port: 587, smtp_auth: "plain", smtp_tls: "1" }.merge(overrides)
        end

        def get_settings
          get edit_tool_path(@tool), headers: { "Turbo-Frame" => "edit-tool-form" }
          assert_response :success
        end

        def assert_labels_point_at_fields(scope)
          labels = css_select("#{scope} label[for]")
          assert_operator labels.size, :>=, 9

          labels.each do |label|
            assert_select "#{scope} ##{label["for"]}", 1, "The #{label.text.strip} label points at #{label["for"]}, which isn't there"
          end
        end
    end
  end
end
