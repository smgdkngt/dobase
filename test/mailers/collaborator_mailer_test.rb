# frozen_string_literal: true

require "test_helper"

class CollaboratorMailerTest < ActionMailer::TestCase
  setup do
    @tool = tools(:shared_board)
    @inviter = users(:one)
    @invitation = Invitation.create!(tool: @tool, email: "guest@example.com", invited_by: @inviter)
  end

  test "invitation has the inviter and tool in the subject" do
    mail = CollaboratorMailer.invitation(@invitation)

    assert_equal [ "guest@example.com" ], mail.to
    assert_equal "#{@inviter.name} invited you to collaborate on #{@tool.name}", mail.subject
  end

  test "invitation comes from the configured app sender" do
    mail = CollaboratorMailer.invitation(@invitation)

    expected = "#{Rails.application.config.x.app.name} <#{Rails.application.config.x.app.from_email}>"
    assert_equal [ Rails.application.config.x.app.from_email ], mail.from
    assert_equal expected, mail[:from].decoded
  end

  test "invitation body links to the acceptance url and mentions the tool" do
    mail = CollaboratorMailer.invitation(@invitation)

    accept_url = "http://example.com/invitations/#{@invitation.token}/accept"
    assert_includes mail.text_part.body.to_s, accept_url
    assert_includes mail.text_part.body.to_s, @tool.name
    assert_includes mail.text_part.body.to_s, @inviter.name
    assert_includes mail.html_part.body.to_s, accept_url
  end

  test "invitation mentions the 7-day expiry" do
    mail = CollaboratorMailer.invitation(@invitation)

    assert_includes mail.text_part.body.to_s, "7 days"
  end
end
