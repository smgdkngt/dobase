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

      private
        def get_settings
          get edit_tool_path(@tool), headers: { "Turbo-Frame" => "edit-tool-form" }
          assert_response :success
        end
    end
  end
end
