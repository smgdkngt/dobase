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
      # The SVG the browser gets is served to mail clients as the PNG beside it
      assert_includes body, "http://example.com/icon.png"
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

  test "a png logo is used as it is, since mail clients draw no svg" do
    with_app_config(name: "Acme Workspace", logo_path: "/icon-192.png") do
      assert_includes PasswordsMailer.reset(@user).html_part.body.to_s, "http://example.com/icon-192.png"
    end
  end

  test "custom branding env vars flow through to the rendered mail" do
    with_app_config(name: "Acme Workspace", logo_path: "/brand/acme.svg") do
      mail = PasswordsMailer.reset(@user)

      assert_includes mail.html_part.body.to_s, "Acme Workspace"
      # No PNG lies next to that SVG, so the header is the name on its own
      assert_not_includes mail.html_part.body.to_s, "/brand/acme"
      assert_includes mail.text_part.body.to_s, "Acme Workspace"
    end
  end

  test "the logo a mail shows is the app's, not the placeholder a new Rails app comes with" do
    assert_equal Rails.public_path.join("icon-512.png").binread, Rails.public_path.join("icon.png").binread
  end

  test "without a theme a mail is in the app's own look, light and dark" do
    body = PasswordsMailer.reset(@user).html_part.body.to_s

    assert_includes body, "background-color: #f5f5f7"
    assert_includes body, "prefers-color-scheme: dark"
    assert_includes body, %(<meta name="color-scheme" content="light dark">)
    assert_includes body, "-apple-system"
  end

  test "a mail wears the theme its reader has in Dobase" do
    @user.choose_theme("tokyo-night")
    tokens = Theme.find("tokyo-night").tokens

    each_mail(only_to: @user) do |mail|
      body = mail.html_part.body.to_s

      assert_includes body, "background-color: #{tokens["--color-sidebar-bg"]}", mail.subject
      assert_includes body, "background-color: #{tokens["--color-background-secondary"]}"
      assert_includes body, "color: #{tokens["--color-text-primary"]}"
      assert_includes body, %(<meta name="color-scheme" content="dark">)
      # A theme is one look: the app's dark set would recolour it for readers in dark mode
      assert_not_includes body, "prefers-color-scheme"
      assert_no_match(/#f5f5f7|#1d1d1f|#0071e3|#86868b/, body)
      # The logo comes in the theme's accent, with its letter in what reads on that
      logo = "http://example.com/logos/#{tokens["--color-accent-solid"].delete("#")}-#{tokens["--color-text-inverse"].delete("#")}.png"
      assert_includes body, logo
    end
  end

  test "a button in a themed mail is the theme's accent with what reads on it" do
    @user.choose_theme("tokyo-night")
    tokens = Theme.find("tokyo-night").tokens

    body = PasswordsMailer.reset(@user).html_part.body.to_s

    assert_includes body, "background-color: #{tokens["--color-accent-solid"]};"
    assert_includes body, "color: #{tokens["--color-text-inverse"]}; text-decoration: none"
  end

  test "a mail to someone without an account stays in the app's own look, whatever the sender wears" do
    @inviter.choose_theme("tokyo-night")

    body = CollaboratorMailer.invitation(@invitation).html_part.body.to_s

    assert_includes body, "background-color: #f5f5f7"
    assert_includes body, "http://example.com/icon.png"
  end

  test "a reader who set the app in monospace gets the mail in it" do
    @user.choose_typeface("mono")

    body = PasswordsMailer.reset(@user).html_part.body.to_s

    assert_includes body, "font-family: ui-monospace"
    assert_not_includes body, "-apple-system"
  end

  test "a logo of your own stays as it is in a themed mail" do
    @user.choose_theme("tokyo-night")

    with_app_config(name: "Acme Workspace", logo_path: "/icon-192.png") do
      body = PasswordsMailer.reset(@user).html_part.body.to_s

      assert_includes body, "http://example.com/icon-192.png"
      assert_not_includes body, "/logos/"
    end
  end

  private
    def each_mail(only_to: nil, &block)
      mails = [
        PasswordsMailer.reset(@user),
        CollaboratorMailer.invitation(@invitation),
        NotificationDigestMailer.digest(@user, deliver_notifications)
      ]
      mails = mails.select { |mail| mail.to == [ only_to.email_address ] } if only_to
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
