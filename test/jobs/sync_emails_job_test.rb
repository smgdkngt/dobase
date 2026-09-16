# frozen_string_literal: true

require "test_helper"

class SyncEmailsJobTest < ActiveJob::TestCase
  test "runs one sync per account at a time and drops the extra requests" do
    assert_equal SyncEmailsJob.new(5).concurrency_key, SyncEmailsJob.new(5).concurrency_key
    assert_not_equal SyncEmailsJob.new(5).concurrency_key, SyncEmailsJob.new(6).concurrency_key
    assert_equal :discard, SyncEmailsJob.concurrency_on_conflict
  end
end
