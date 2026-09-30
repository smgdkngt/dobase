module ApiTestHelper
  # Headers for a JSON API request authenticated with a fresh access token.
  def api_headers(user, permission: "write", name: "Test token", agent: false)
    token = user.access_tokens.create!(name: name, permission: permission, agent: agent).token
    { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include ApiTestHelper
end
