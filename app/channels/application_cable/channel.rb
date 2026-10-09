module ApplicationCable
  class Channel < ActionCable::Channel::Base
    # A connection made with an access token opens no channel but one that says so,
    # the way a controller's actions do (Authentication.allow_access_tokens): the
    # channels of the app's pages carry what is in a chat, a document and a tool.
    # Kept on the class only: a channel's public methods are what a connection can call
    class_attribute :access_tokens_allowed, default: false, instance_accessor: false, instance_predicate: false

    def self.allow_access_tokens
      self.access_tokens_allowed = true
    end

    before_subscribe :refuse_access_token

    private
      def refuse_access_token
        return if access_token.nil? || self.class.access_tokens_allowed

        reject
        # Without this the channel's own `subscribed` would still run, and stream
        throw :abort
      end
  end
end
