module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user, :access_token

    def connect
      set_current_user || reject_unauthorized_connection
    end

    private
      # A connection that carries an access token is that token's alone, as a request
      # is (Authentication): it never falls back on a session. What it may open is one
      # channel, EventsChannel (ApplicationCable::Channel refuses it the others).
      def set_current_user
        if request.authorization.to_s.start_with?("Bearer ")
          token, = ActionController::HttpAuthentication::Token.token_and_options(request)
          if (self.access_token = AccessToken.authenticate(token))
            access_token.record_usage
            self.current_user = access_token.user
          end
        elsif session = Session.find_by(id: cookies.signed[:session_id])
          self.current_user = session.user
        end
      end
  end
end
