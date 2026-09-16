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

      private
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
