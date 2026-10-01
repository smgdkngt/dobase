# frozen_string_literal: true

# A document's shared copy (the Yjs changes its editors write in) is thrown away
# when the text is replaced from outside the editor. This counts how often, so a
# page still holding an older copy can be told apart from one writing in this one.
class AddSharedCopyGenerationToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :shared_copy_generation, :integer, default: 0, null: false
  end
end
