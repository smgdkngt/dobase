# frozen_string_literal: true

module Docs
  # One change to a document's shared copy, as Yjs encodes it. A document's
  # text is the sum of these, applied in order; the browsers do the applying,
  # Dobase only keeps them and hands them to whoever joins next.
  #
  # The pile is folded back into a single row now and then (see
  # DocumentSyncChannel), because only a browser can merge them.
  class Update < ApplicationRecord
    self.table_name = "document_updates"

    belongs_to :document, class_name: "Docs::Document"

    scope :oldest_first, -> { order(:id) }
  end
end
