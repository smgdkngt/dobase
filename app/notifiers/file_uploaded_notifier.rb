# frozen_string_literal: true

class FileUploadedNotifier < Noticed::Event
  required_params :file, :uploader, :tool

  deliver_by :custom_action_cable,
    class: "Noticed::DeliveryMethods::CustomActionCable",
    stream: -> { "notifications:#{recipient.id}" },
    message: -> { I18n.with_locale(Translation.supported(recipient.try(:locale)) || I18n.default_locale) { notification_data } }

  notification_methods do
    def message
      uploader = event.params[:uploader]
      file = event.params[:file]
      _("%{person} uploaded %{file}", person: uploader&.name || _("Someone"), file: file&.name || _("a file"))
    end

    def url
      tool = event.params[:tool]
      tool ? tool_files_path(tool) : root_path
    end

    def icon_name
      "upload"
    end

    def notification_data
      {
        id: id,
        type: "FileUploadedNotifier",
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
