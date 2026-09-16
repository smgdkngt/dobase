# frozen_string_literal: true

require "test_helper"

class RemoteHostTest < ActiveSupport::TestCase
  test "public servers are fine" do
    assert_equal "imap.example.com", RemoteHost.verify!("imap.example.com")
    assert_equal "93.184.216.34", RemoteHost.verify!("93.184.216.34")
  end

  test "local addresses are refused" do
    %w[127.0.0.1 localhost 0.0.0.0 169.254.169.254 ::1 [::1] ::ffff:127.0.0.1 fe80::1].each do |host|
      error = assert_raises(RemoteHost::Forbidden, host) { RemoteHost.verify!(host) }
      assert_match "local address", error.message
    end
  end

  test "private networks are refused unless allowed" do
    %w[10.0.0.5 172.20.0.3 192.168.1.10 100.100.1.1 fd00::1].each do |host|
      error = assert_raises(RemoteHost::Forbidden, host) { RemoteHost.verify!(host) }
      assert_match "ALLOW_PRIVATE_NETWORK_HOSTS=true", error.message
    end

    with_env("ALLOW_PRIVATE_NETWORK_HOSTS" => "true") do
      assert_equal "192.168.1.10", RemoteHost.verify!("192.168.1.10")
      assert_raises(RemoteHost::Forbidden) { RemoteHost.verify!("127.0.0.1") }
    end
  end

  test "a name that resolves to a private address is refused" do
    assert_raises(RemoteHost::Forbidden) { RemoteHost.verify!("mail.internal") }
  end

  test "a name that doesn't resolve or is missing is refused" do
    assert_match "could not be found", assert_raises(RemoteHost::Forbidden) { RemoteHost.verify!("nowhere.invalid") }.message
    assert_raises(RemoteHost::Forbidden) { RemoteHost.verify!("") }
  end

  private

  def with_env(values)
    previous = values.keys.to_h { |key| [ key, ENV[key] ] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end
end
