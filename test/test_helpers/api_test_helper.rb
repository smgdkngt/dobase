module ApiTestHelper
  # Headers for a JSON API request authenticated with a fresh access token.
  def api_headers(user, permission: "write")
    token = user.access_tokens.create!(name: "Test token", permission: permission).token
    { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include ApiTestHelper
end
