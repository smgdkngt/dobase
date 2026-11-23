# frozen_string_literal: true

require "test_helper"

class Mails::IdleTest < ActiveSupport::TestCase
  test "the mailboxes used lately are watched" do
    collaborators(:one_my_mail).update!(last_seen_at: 1.hour.ago)
    collaborators(:two_other_mail).update!(last_seen_at: 3.days.ago)

    assert_equal [ mails_accounts(:primary).id ], Mails::Idle.wanted_account_ids
  end

  test "a mailbox whose login was refused lately is not" do
    collaborators(:one_my_mail).update!(last_seen_at: 1.hour.ago)
    mails_accounts(:primary).mark_sync_error!(Mails::Account::AUTHENTICATION_FAILED)

    assert_empty Mails::Idle.wanted_account_ids
  end

  test "nothing is watched in the demo" do
    with_env("DEMO_MODE" => "true") { assert_not Mails::Idle.enabled? }
    with_env("MAIL_IDLE" => "false") { assert_not Mails::Idle.enabled? }
    assert Mails::Idle.enabled?
  end

  private
    def with_env(values)
      before = values.keys.index_with { |key| ENV[key] }
      values.each { |key, value| ENV[key] = value }
      yield
    ensure
      before.each { |key, value| ENV[key] = value }
    end
end
