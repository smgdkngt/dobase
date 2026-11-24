# frozen_string_literal: true

class DocumentCreatedNotifier < Noticed::Event
  required_params :document, :creator, :tool

  deliver_by :custom_action_cable,
    class: "Noticed::DeliveryMethods::CustomActionCable",
    stream: -> { "notifications:#{recipient.id}" },
    message: -> { I18n.with_locale(Translation.supported(recipient.try(:locale)) || I18n.default_locale) { notification_data } }

  notification_methods do
    def message
      creator = event.params[:creator]
      document = event.params[:document]
      _("%{person} created %{document}", person: creator&.name || _("Someone"), document: document&.title || _("a document"))
    end

    def url
      tool = event.params[:tool]
      document = event.params[:document]
      tool && document ? tool_docs_document_path(tool, document) : root_path
    end

    def icon_name
      "file-plus"
    end

    def notification_data
      {
        id: id,
        type: "DocumentCreatedNotifier",
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
