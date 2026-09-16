# frozen_string_literal: true

# Stands in for the SMTP server, so no test sends real email.
module SmtpTestHelper
  class FakeSmtp
    attr_reader :deliveries

    def initialize
      @deliveries = []
    end

    def start(*)
      yield self
    end

    def send_message(message, from, recipients)
      @deliveries << { message: message, from: from, recipients: recipients }
    end
  end

  # Email that SmtpSendService sends in the block, the app server's included, goes
  # to a FakeSmtp. Returns what the mail server would have been given.
  def capture_smtp_deliveries
    smtp = FakeSmtp.new
    SmtpSendService.singleton_class.define_method(:new) do |*args|
      super(*args).tap { |service| service.define_singleton_method(:build_smtp) { smtp } }
    end
    yield
    smtp.deliveries
  ensure
    SmtpSendService.singleton_class.remove_method(:new)
  end
end

ActiveSupport.on_load(:active_support_test_case) do
  include SmtpTestHelper
end
