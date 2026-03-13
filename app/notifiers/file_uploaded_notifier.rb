# frozen_string_literal: true

class FileUploadedNotifier < Noticed::Event
  required_params :file, :uploader, :tool

  deliver_by :custom_action_cable,
    class: "Noticed::DeliveryMethods::CustomActionCable",
    stream: -> { "notifications:#{recipient.id}" },
    message: -> { notification_data }

  notification_methods do
    def message
      uploader = event.params[:uploader]
      file = event.params[:file]
      "#{uploader&.name || 'Someone'} uploaded #{file&.name || 'a file'}"
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
