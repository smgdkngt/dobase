# frozen_string_literal: true

require "fileutils"
require "json"

module Dobase
  # Where the CLI finds its server and token. DOBASE_URL and DOBASE_TOKEN
  # override the saved config, which lives in ~/.config/dobase/config.json.
  class Config
    def self.path
      File.join(ENV.fetch("XDG_CONFIG_HOME", File.join(Dir.home, ".config")), "dobase", "config.json")
    end

    def url
      (ENV["DOBASE_URL"] || saved["url"])&.chomp("/")
    end

    def token
      ENV["DOBASE_TOKEN"] || saved["token"]
    end

    def save(url:, token:)
      FileUtils.mkdir_p(File.dirname(self.class.path), mode: 0o700)
      File.write(self.class.path, JSON.pretty_generate(url: url.chomp("/"), token: token))
      File.chmod(0o600, self.class.path)
      @saved = nil
    end

    def forget
      FileUtils.rm_f(self.class.path)
      @saved = nil
    end

    private

    def saved
      @saved ||= File.exist?(self.class.path) ? JSON.parse(File.read(self.class.path)) : {}
    end
  end
end
