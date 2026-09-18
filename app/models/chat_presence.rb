# frozen_string_literal: true

# Counts a person's live chat subscriptions, so several open tabs read as one
# person being there: only the first connection makes them online, and only the
# last one to go makes them offline. Without this, closing one tab announced
# "offline" for someone still sitting in another one.
#
# The count is per process, which is all a single subscription's arrival and
# departure needs — both run on the same server that holds the connection. A
# tab on another process that gets marked offline by mistake says hello again
# (see chat_controller.js), which puts it back.
class ChatPresence
  @lock = Mutex.new
  @connections = Hash.new(0)

  class << self
    # True when this is the person's first connection to the chat.
    def connect(chat_id, user_id)
      @lock.synchronize do
        key = key_for(chat_id, user_id)
        @connections[key] += 1
        @connections[key] == 1
      end
    end

    # True when this was the person's last connection to the chat.
    def disconnect(chat_id, user_id)
      @lock.synchronize do
        key = key_for(chat_id, user_id)
        return true unless @connections.key?(key)

        @connections[key] -= 1
        @connections.delete(key) if @connections[key] <= 0
        !@connections.key?(key)
      end
    end

    def connections(chat_id, user_id)
      @lock.synchronize { @connections[key_for(chat_id, user_id)] }
    end

    def reset!
      @lock.synchronize { @connections.clear }
    end

    private

    def key_for(chat_id, user_id)
      [ chat_id.to_i, user_id.to_i ]
    end
  end
end
