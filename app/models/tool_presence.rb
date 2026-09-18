# frozen_string_literal: true

# Counts a person's live subscriptions to a tool, so several open tabs read as
# one person being there: only the first connection announces them, and only the
# last one to go says they left. The same idea as [ChatPresence], for every tool.
#
# The count is per process, which is all one subscription's arrival and
# departure needs — both run on the server that holds the connection. A tab on
# another process that is dropped by mistake says hello again on its next
# heartbeat, which puts the person back on everyone's list.
class ToolPresence
  @lock = Mutex.new
  @connections = Hash.new(0)

  class << self
    # True when this is the person's first connection to the tool.
    def connect(tool_id, user_id)
      @lock.synchronize do
        key = key_for(tool_id, user_id)
        @connections[key] += 1
        @connections[key] == 1
      end
    end

    # True when this was the person's last connection to the tool.
    def disconnect(tool_id, user_id)
      @lock.synchronize do
        key = key_for(tool_id, user_id)
        return true unless @connections.key?(key)

        @connections[key] -= 1
        @connections.delete(key) if @connections[key] <= 0
        !@connections.key?(key)
      end
    end

    def connections(tool_id, user_id)
      @lock.synchronize { @connections[key_for(tool_id, user_id)] }
    end

    def reset!
      @lock.synchronize { @connections.clear }
    end

    private

    def key_for(tool_id, user_id)
      [ tool_id.to_i, user_id.to_i ]
    end
  end
end
