# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Dobase
  class Error < StandardError; end

  class ApiError < Error
    attr_reader :status

    def initialize(status, message)
      @status = status
      super("#{message} (HTTP #{status})")
    end
  end

  # Thin JSON-over-HTTP wrapper around the Dobase API.
  class Client
    CONTENT_TYPES = {
      ".csv" => "text/csv", ".doc" => "application/msword",
      ".docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      ".gif" => "image/gif", ".htm" => "text/html", ".html" => "text/html", ".ics" => "text/calendar",
      ".jpeg" => "image/jpeg", ".jpg" => "image/jpeg", ".json" => "application/json", ".md" => "text/markdown",
      ".mov" => "video/quicktime", ".mp3" => "audio/mpeg", ".mp4" => "video/mp4", ".ogg" => "audio/ogg",
      ".pdf" => "application/pdf", ".png" => "image/png", ".ppt" => "application/vnd.ms-powerpoint",
      ".pptx" => "application/vnd.openxmlformats-officedocument.presentationml.presentation",
      ".svg" => "image/svg+xml", ".txt" => "text/plain", ".wav" => "audio/wav", ".webm" => "video/webm",
      ".webp" => "image/webp", ".xls" => "application/vnd.ms-excel",
      ".xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", ".zip" => "application/zip"
    }.freeze

    def initialize(url:, token:, user_agent:)
      raise Error, "Not signed in. Run `dobase login URL` first, or set DOBASE_URL and DOBASE_TOKEN." if url.nil? || token.nil?

      @base = URI(url)
      @token = token
      @user_agent = user_agent
    end

    def get(path, params = {})
      uri = uri_for(path)
      uri.query = URI.encode_www_form(params.compact) unless params.compact.empty?
      perform(Net::HTTP::Get.new(uri))
    end

    def post(path, body = {}) = perform_with_body(Net::HTTP::Post, path, body)
    def patch(path, body = {}) = perform_with_body(Net::HTTP::Patch, path, body)
    def delete(path, body = {}) = perform_with_body(Net::HTTP::Delete, path, body)

    # Multipart POST. `files` maps a form field to one or more local paths.
    def upload(path, files:, fields: {})
      request = Net::HTTP::Post.new(uri_for(path))
      parts = fields.compact.map { |name, value| [ name.to_s, value.to_s ] }
      handles = files.flat_map do |name, paths|
        Array(paths).map do |file_path|
          handle = File.open(file_path, "rb")
          parts << [ name.to_s, handle, { filename: File.basename(file_path), content_type: content_type_for(file_path) } ]
          handle
        end
      end
      request.set_form(parts, "multipart/form-data")
      perform(request)
    ensure
      handles&.each(&:close)
    end

    # Streams a download to `destination`, following redirects (e.g. to file storage).
    # Returns the filename the server suggested, if any.
    def download(path, destination, redirects: 5)
      uri = path.is_a?(URI) ? path : uri_for(path)

      http_for(uri).request(authorize(Net::HTTP::Get.new(uri), uri)) do |response|
        case response
        when Net::HTTPRedirection
          raise Error, "Too many redirects" if redirects.zero?
          return download(URI.join(uri, response["location"]), destination, redirects: redirects - 1)
        when Net::HTTPSuccess
          File.open(destination, "wb") { |file| response.read_body { |chunk| file.write(chunk) } }
          return response["content-disposition"].to_s[/filename="([^"]+)"/, 1]
        else
          raise ApiError.new(response.code.to_i, error_message(response.body))
        end
      end
    end

    private

    def uri_for(path)
      path.start_with?("http://", "https://") ? URI(path) : URI.join("#{@base}/", path.delete_prefix("/"))
    end

    def perform_with_body(request_class, path, body)
      request = request_class.new(uri_for(path))
      unless body.nil? || body.empty?
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)
      end
      perform(request)
    end

    def perform(request)
      response = http_for(request.uri).request(authorize(request, request.uri))

      case response
      when Net::HTTPNoContent
        nil
      when Net::HTTPSuccess
        response.body.to_s.strip.empty? ? nil : JSON.parse(response.body)
      when Net::HTTPRedirection
        raise Error, "The server redirected to #{response["location"]} instead of answering. " \
          "This action may not be available through the API."
      else
        raise ApiError.new(response.code.to_i, error_message(response.body))
      end
    rescue JSON::ParserError
      raise Error, "The server sent something other than JSON (HTTP #{response.code})."
    rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => error
      raise Error, "Could not reach #{@base}: #{error.message}"
    end

    # The token only goes to the configured server, never to a redirect target elsewhere.
    def authorize(request, uri)
      request["Accept"] = "application/json"
      request["User-Agent"] = @user_agent
      request["Authorization"] = "Bearer #{@token}" if uri.host == @base.host && uri.port == @base.port
      request
    end

    def http_for(uri)
      Net::HTTP.new(uri.host, uri.port).tap do |http|
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 10
        http.read_timeout = 60
      end
    end

    def error_message(body)
      data = JSON.parse(body.to_s)
      Array(data["errors"] || data["error"]).join(", ")
    rescue JSON::ParserError
      body.to_s.strip.lines.first.to_s.strip.then { |line| line.empty? ? "Request failed" : line[0, 200] }
    end

    def content_type_for(path)
      CONTENT_TYPES.fetch(File.extname(path).downcase, "application/octet-stream")
    end
  end
end
