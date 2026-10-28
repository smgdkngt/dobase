# frozen_string_literal: true

# A mail or calendar account that hasn't synced for a day: its tool's owners hear it
# once (EncryptedPassword#tell_owners_of_stall), in the app and in their digest.
class SyncStalledNotifier < Noticed::Event
  required_params :account, :tool, :since

  deliver_by :custom_action_cable,
    class: "Noticed::DeliveryMethods::CustomActionCable",
    stream: -> { "notifications:#{recipient.id}" },
    message: -> { notification_data }

  notification_methods do
    def message
      account = event.params[:account]
      what = account.is_a?(Calendars::Account) ? "The calendar" : "Mail for #{account&.email_address || 'this tool'}"
      since = Time.zone.parse(event.params[:since].to_s)
      text = "#{what} hasn't synced since #{since ? ApplicationController.helpers.format_datetime(since) : 'a day ago'}"
      error = event.params[:error].presence
      error ? "#{text}: #{error}" : text
    end

    # The tool's settings, at the account's tab
    def url
      tool = event.params[:tool]
      return root_path unless tool

      edit_tool_path(tool, tab: event.params[:account].is_a?(Calendars::Account) ? "calendar" : "email")
    end

    def icon_name
      "alert-circle"
    end

    def notification_data
      {
        id: id,
        type: "SyncStalledNotifier",
        tool_id: event.params[:tool]&.id,
        message: message,
        url: url,
        icon: icon_name,
        read_at: read_at,
        created_at: created_at.iso8601
      }
    end
  end
end
