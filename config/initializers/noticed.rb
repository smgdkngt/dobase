# frozen_string_literal: true

# A notification keeps what it is about as references to records: the message,
# who sent it, the tool. Noticed reads them back all at once, and when one of
# them has been deleted it gives up on all of them — so deleting a chat message
# left "Someone sent a message in a chat", linking nowhere, and with no tool to
# tell them apart every such notification was folded into one line.
#
# Here only the record that is gone reads as nil, which is what the notifiers
# already expect (`sender&.name || "Someone"`), and the rest stays what it was.
module KeepNotificationParamsThatStillExist
  def load(data)
    params = super
    return params unless data.is_a?(Hash) && lost?(params)

    super(data.transform_values { |value| value unless lost?(super(value)) })
  end

  private

  # What Noticed hands back in place of params it couldn't find a record for
  def lost?(params)
    params.is_a?(Hash) && params.key?(:noticed_error)
  end
end

Noticed::Coder.singleton_class.prepend(KeepNotificationParamsThatStillExist)
