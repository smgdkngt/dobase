# frozen_string_literal: true

class CreateDocumentUpdates < ActiveRecord::Migration[8.1]
  def change
    create_table :document_updates do |t|
      t.references :document, null: false, foreign_key: { to_table: :documents }
      t.binary :data, null: false
      t.boolean :seed, null: false, default: false
      t.datetime :created_at, null: false
    end

    # Only one page ever fills a document's shared copy from the text that was
    # already saved; the rest join the copy that page made.
    add_index :document_updates, :document_id, unique: true, where: "seed = 1", name: "index_document_updates_on_seed"
  end
end
