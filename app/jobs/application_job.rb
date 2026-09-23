class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  # Jobs that talk to mail and calendar servers. The demo has none to talk to, so
  # they're neither queued nor run there.
  def self.skip_in_demo
    before_enqueue { throw :abort if Demo.enabled? }
    before_perform { throw :abort if Demo.enabled? }
  end
end
