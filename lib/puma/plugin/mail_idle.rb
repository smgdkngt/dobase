# frozen_string_literal: true

require "puma/plugin"

Puma::Plugin.create do
  def start(launcher)
    return if launcher.options[:workers].to_i.positive?

    launcher.events.after_booted { Mails::Idle.start }
    launcher.events.after_stopped { Mails::Idle.stop }
    launcher.events.before_restart { Mails::Idle.stop }
  end
end
