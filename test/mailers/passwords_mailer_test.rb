# frozen_string_literal: true

require "test_helper"

class PasswordsMailerTest < ActionMailer::TestCase
  setup do
    @user = users(:one)
  end

  test "reset email is addressed to the user with a clear subject" do
    mail = PasswordsMailer.reset(@user)

    assert_equal [ @user.email_address ], mail.to
    assert_equal "Reset your password", mail.subject
  end

  test "reset email links to the edit_password page with a valid token" do
    mail = PasswordsMailer.reset(@user)

    body = mail.text_part.body.to_s
    assert_match %r{http://example\.com/passwords/[^/\s]+/edit}, body

    token = body[%r{passwords/([^/\s]+)/edit}, 1]
    assert_equal @user, User.find_by_password_reset_token!(token)
  end

  test "reset email mentions how long the link is valid" do
    mail = PasswordsMailer.reset(@user)

    # The exact phrasing depends on the token expiry, but the email should
    # always communicate that the link expires.
    assert_match(/expire/i, mail.text_part.body.to_s)
  end
end
