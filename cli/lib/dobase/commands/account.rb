# frozen_string_literal: true

require "io/console"

module Dobase
  module Commands
    class Account < Command
      command "login", "Save the server URL and an access token for this machine", args: %w[[URL]] do |url = nil|
        url = (url || config.url || ask("Dobase URL: ")).to_s.strip.chomp("/")
        url = "https://#{url}" unless url.match?(%r{\Ahttps?://})

        $stderr.puts "Create an access token under Profile → API: #{url}/profile/edit?tab=api"
        token = ask("Access token: ", secret: true).to_s.strip
        raise UsageError, "No token given." if token.empty?

        @client = Client.new(url: url, token: token, user_agent: @user_agent)
        profile = get("/profile")
        config.save(url: url, token: token)

        say "Signed in to #{url} as #{person(profile)}."
        say "Token #{quoted(profile.dig("access_token", "name"))} can #{profile.dig("access_token", "permission") == "write" ? "read and write" : "only read"}."
      end

      command "logout", "Forget the saved URL and token (revoke the token under Profile → API)" do
        config.forget
        say "Signed out. The token still works until you revoke it under Profile → API."
      end

      command "whoami", "Show who the token belongs to and what it may do" do
        output(me) do |profile|
          token = profile["access_token"]
          say "#{person(profile)} on #{config.url}"
          say "Token #{quoted(token["name"])} (#{token["permission"] == "write" ? "read and write" : "read only"})" if token
        end
      end

      private

      # Prompts only when someone is typing; a piped token is read silently.
      def ask(prompt, secret: false)
        return $stdin.gets unless $stdin.tty?

        $stderr.print prompt
        value = secret ? $stdin.noecho(&:gets) : $stdin.gets
        $stderr.puts if secret
        value
      end
    end
  end
end
