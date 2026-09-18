# frozen_string_literal: true

# Counts a person's live subscriptions to a document, so several open tabs read
# as one person: closing one tab must not say they stopped editing while they
# are still typing in another. The same idea as [ChatPresence] and
# [ToolPresence].
#
# The count is per process, which is all one subscription's arrival and
# departure needs. A tab on another process that is let go by mistake says so
# again on its next change, which takes the document back.
class DocumentPresence
  @lock = Mutex.new
  @connections = Hash.new(0)

  class << self
    # True when this is the person's first connection to the document.
    def connect(document_id, user_id)
      @lock.synchronize do
        key = key_for(document_id, user_id)
        @connections[key] += 1
        @connections[key] == 1
      end
    end

    # True when this was the person's last connection to the document.
    def disconnect(document_id, user_id)
      @lock.synchronize do
        key = key_for(document_id, user_id)
        return true unless @connections.key?(key)

        @connections[key] -= 1
        @connections.delete(key) if @connections[key] <= 0
        !@connections.key?(key)
      end
    end

    def connections(document_id, user_id)
      @lock.synchronize { @connections[key_for(document_id, user_id)] }
    end

    def reset!
      @lock.synchronize { @connections.clear }
    end

    private

    def key_for(document_id, user_id)
      [ document_id.to_i, user_id.to_i ]
    end
  end
end
