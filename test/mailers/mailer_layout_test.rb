# frozen_string_literal: true

require "test_helper"

class MailerLayoutTest < ActionMailer::TestCase
  setup do
    @user = users(:one)
    @tool = tools(:shared_board)
    @inviter = users(:two)
    @invitation = Invitation.create!(tool: @tool, email: "guest@example.com", invited_by: @inviter)
  end

  test "every mail has both a text and an html part" do
    each_mail do |mail|
      assert mail.multipart?, "expected #{mail.subject.inspect} to be multipart"
      assert mail.text_part.present?, "expected #{mail.subject.inspect} to have a text part"
      assert mail.html_part.present?, "expected #{mail.subject.inspect} to have an html part"
      assert mail.text_part.body.to_s.present?
      assert mail.html_part.body.to_s.present?
    end
  end

  test "every html mail shows the configured app name and an absolute logo url" do
    each_mail do |mail|
      body = mail.html_part.body.to_s
      assert_includes body, Rails.application.config.x.app.name
      assert_includes body, "http://example.com#{Rails.application.config.x.app.logo_path}"
    end
  end

  test "every mail links absolutely, never with a relative path" do
    each_mail do |mail|
      [ mail.text_part, mail.html_part ].each do |part|
        part.body.to_s.scan(%r{href="([^"]+)"}).flatten.each do |href|
          assert_match(%r{\Ahttps?://}, href, "expected an absolute link, got #{href.inspect}")
        end
      end
    end
  end

  test "custom branding env vars flow through to the rendered mail" do
    with_app_config(name: "Acme Workspace", logo_path: "/brand/acme.svg") do
      mail = PasswordsMailer.reset(@user)

      assert_includes mail.html_part.body.to_s, "Acme Workspace"
      assert_includes mail.html_part.body.to_s, "http://example.com/brand/acme.svg"
      assert_includes mail.text_part.body.to_s, "Acme Workspace"
    end
  end

  private
    def each_mail(&block)
      mails = [
        PasswordsMailer.reset(@user),
        CollaboratorMailer.invitation(@invitation),
        NotificationDigestMailer.digest(@user, deliver_notifications)
      ]
      mails.each(&block)
    end

    def deliver_notifications
      CardAssignmentNotifier.with(card: cards(:first_task), assigner: @inviter, tool: @tool).deliver(@user)
      @user.notifications.reload.last(1)
    end

    def with_app_config(name:, logo_path:)
      app_config = Rails.application.config.x.app
      original_name = app_config.name
      original_logo_path = app_config.logo_path
      app_config.name = name
      app_config.logo_path = logo_path
      yield
    ensure
      app_config.name = original_name
      app_config.logo_path = original_logo_path
    end
end
