# frozen_string_literal: true

# Who a request comes from is what kamal-proxy says in X-Forwarded-For. A Client-IP
# header is whatever the client wrote there, and when it disagrees Rails raises
# IpSpoofAttackError and answers 500 (a scanner or a corporate proxy sending one).
# Nothing in front of the app sets it, so it is dropped before Rails reads the address.
class WithoutClientIp
  def initialize(app)
    @app = app
  end

  def call(env)
    env.delete("HTTP_CLIENT_IP")
    @app.call(env)
  end
end
