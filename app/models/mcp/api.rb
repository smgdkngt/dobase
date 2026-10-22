# frozen_string_literal: true

module Mcp
  # The JSON API, asked from inside the process. An MCP tool does what the
  # dobase CLI does for the same command: it sends the API request, with the
  # token the client sent to `/mcp`, and hands back the JSON. So everything the
  # API decides decides here too: who may open which tool, what a token may do
  # (read-only tokens, nothing on accounts or sharing), who wrote something,
  # the events, the pages that redraw themselves, the demo's limits.
  #
  # The request goes to the router, past the middleware: the executor around
  # the `/mcp` request already runs (a second one would reset it), and the
  # rest is about browsers and sessions, which a token request doesn't have.
  class Api
    BOUNDARY = "DobaseMcp#{SecureRandom.hex(8)}"
    class Error < StandardError
      attr_reader :status, :body

      def initialize(status, body)
        @status = status
        @body = body
        super(self.class.message_for(status, body))
      end

      def self.message_for(status, body)
        detail = body["error"].presence || Array(body["errors"]).to_sentence.presence if body.is_a?(Hash)
        detail ||= Rack::Utils::HTTP_STATUS_CODES[status]
        case status
        when 401 then "Not signed in: the connection has ended."
        when 403 then detail == "Forbidden" ? "Not allowed with this connection." : detail
        when 404 then "Not found, or not shared with you."
        else detail.to_s
        end
      end
    end

    # Where the `/mcp` request came from, so the API's links point at the same server
    def initialize(token:, host:, https:, remote_ip: "127.0.0.1")
      @token = token
      @host = host
      @https = https
      @remote_ip = remote_ip
    end

    def get(path, params = {})
      request("GET", path, query: params.compact_blank)
    end

    def post(path, body = {})
      request("POST", path, body:)
    end

    def patch(path, body = {})
      request("PATCH", path, body:)
    end

    def delete(path, params = {})
      request("DELETE", path, query: params.compact_blank)
    end

    # A multipart form, for files: params holding Rack::Multipart::UploadedFiles
    def upload(path, params)
      request("POST", path, form: params)
    end

    def url(path)
      "#{@https ? "https" : "http"}://#{@host}#{path}"
    end

    private

    def request(method, path, query: nil, body: nil, form: nil)
      target = query.present? ? "#{path}?#{query.to_query}" : path
      content = if form
        { input: multipart(form), "CONTENT_TYPE" => "multipart/form-data; boundary=#{BOUNDARY}" }
      else
        { input: body.nil? ? "" : body.to_json, "CONTENT_TYPE" => "application/json" }
      end
      env = Rack::MockRequest.env_for(url(target), method:, **content, "HTTP_ACCEPT" => "application/json",
        "HTTP_AUTHORIZATION" => "Bearer #{@token}", "REMOTE_ADDR" => @remote_ip)
      env.merge!(Rails.application.env_config)
      ActionDispatch::Request::Session.disabled(ActionDispatch::Request.new(env))

      status, headers, response = Current.set(session: nil, access_token: nil) { Rails.application.routes.call(env) }
      text = +""
      response.each { |part| text << part }
      response.close if response.respond_to?(:close)
      parsed = parse(text, headers)
      raise Error.new(status, parsed) unless status.between?(200, 299)

      parsed
    end

    # Rack's own builder takes a list of files for a hash, so the form is written here
    def multipart(params)
      body = +"".b
      fields(params).each do |name, value|
        body << "--#{BOUNDARY}\r\n"
        if value.is_a?(Rack::Multipart::UploadedFile)
          filename = value.original_filename.to_s.delete("\"\r\n")
          body << %(content-disposition: form-data; name="#{name}"; filename="#{filename}"\r\n)
          body << "content-type: #{value.content_type}\r\n\r\n" << value.read.b << "\r\n"
        else
          body << %(content-disposition: form-data; name="#{name}"\r\n\r\n) << value.to_s.b << "\r\n"
        end
      end
      body << "--#{BOUNDARY}--\r\n"
    end

    def fields(value, prefix = nil)
      case value
      when Hash then value.flat_map { |key, inner| fields(inner, prefix ? "#{prefix}[#{key}]" : key.to_s) }
      when Array then value.flat_map { fields(it, "#{prefix}[]") }
      else [ [ prefix, value ] ]
      end
    end

    def parse(text, headers)
      return nil if text.blank?
      return text unless headers["content-type"].to_s.include?("json")

      JSON.parse(text)
    end
  end
end
