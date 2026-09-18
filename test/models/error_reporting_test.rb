# frozen_string_literal: true

require "test_helper"

class ErrorReportingTest < ActiveSupport::TestCase
  test "it stays out of the way when no collector is set" do
    with_env("SENTRY_DSN" => nil) do
      assert_not ErrorReporting.enabled?
      assert_nil ErrorReporting.configure!
    end
  end

  test "a collector's address turns it on" do
    with_env("SENTRY_DSN" => "https://public@errors.example.com/1") do
      assert ErrorReporting.enabled?
    end
  end

  test "the answers Rails gives for a bad request are not reported as faults" do
    assert_includes ErrorReporting::ALREADY_HANDLED, "ActiveRecord::RecordNotFound"
    assert_includes ErrorReporting::ALREADY_HANDLED, "ActionController::InvalidAuthenticityToken"
  end

  test "passwords in a request never reach the collector" do
    event = Struct.new(:request).new(Struct.new(:data).new({ "password" => "hunter2", "subject" => "Hi" }))

    ErrorReporting.scrub(event)

    assert_equal "[FILTERED]", event.request.data["password"]
    assert_equal "Hi", event.request.data["subject"]
  end

  private
    def with_env(values)
      previous = values.transform_values { |_| nil }.merge(ENV.slice(*values.keys))
      values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
      yield
    ensure
      previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end
end
