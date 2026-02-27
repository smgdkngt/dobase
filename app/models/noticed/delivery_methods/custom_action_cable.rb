# frozen_string_literal: true

module Noticed
  module DeliveryMethods
    class CustomActionCable < DeliveryMethod
      required_options :message

      def deliver
        ::ActionCable.server.broadcast(stream_name, evaluate_option(:message))
      end

      private

      def stream_name
        evaluate_option(:stream) || "notifications:#{recipient.id}"
      end
    end
  end
end
