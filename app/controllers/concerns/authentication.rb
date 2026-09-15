module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    before_action :reject_access_token
    # Browsers can't attach an Authorization header to a cross-site request, so
    # token-authenticated requests aren't exposed to CSRF.
    skip_forgery_protection if: :access_token_request?
    helper_method :authenticated?, :current_user, :user_signed_in?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end

    # Access tokens only work on actions that opt in, so account, credential
    # and sharing settings stay out of reach of a leaked token.
    def allow_access_tokens(**options)
      skip_before_action :reject_access_token, **options
    end
  end

  private
    def authenticated?
      Current.access_token || resume_session
    end

    def current_user
      Current.user
    end

    def user_signed_in?
      authenticated?.present?
    end

    def require_authentication
      if access_token_request?
        authenticate_with_access_token
      else
        resume_session || request_authentication
      end
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      # A request that carries a token is authenticated by that token alone.
      return if access_token_request?

      Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
    end

    def access_token_request?
      request.authorization.to_s.start_with?("Bearer ")
    end

    def authenticate_with_access_token
      access_token = authenticate_with_http_token { |token, _options| AccessToken.authenticate(token) }

      if access_token.nil?
        response.headers["WWW-Authenticate"] = %(Bearer realm="#{Rails.application.config.x.app.name}")
        render json: { error: "Invalid access token" }, status: :unauthorized
      elsif !access_token.allows?(request.method)
        render json: { error: "This access token is read-only" }, status: :forbidden
      else
        access_token.record_usage
        Current.access_token = access_token
      end
    end

    def reject_access_token
      if Current.access_token
        render json: { error: "This action isn't available to access tokens" }, status: :forbidden
      end
    end

    def request_authentication
      if request.format.json?
        render json: { error: "Authentication required" }, status: :unauthorized
      else
        session[:return_to_after_authenticating] = request.fullpath
        redirect_to new_session_path
      end
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    def start_new_session_for(user)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        cookies.signed.permanent[:session_id] = { value: session.id, httponly: true, same_site: :lax }
      end
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
