# frozen_string_literal: true

module SearchesHelper
  SEARCH_ICONS = {
    card: "layout",
    todo: "check-square",
    document: "file-text",
    folder: "folder",
    file: "file",
    message: "message-circle",
    event: "calendar",
    mail: "mail"
  }.freeze

  def search_icon(kind)
    SEARCH_ICONS.fetch(kind, "search")
  end
end
