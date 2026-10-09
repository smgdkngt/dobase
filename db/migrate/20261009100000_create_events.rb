# frozen_string_literal: true

# What happened in a tool, one row each, for whoever listens from outside the
# browser (`dobase events --follow`). Read by number: "everything after N".
class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :events do |t|
      # No foreign keys: a row outlives its tool, its author and their token for the
      # week it is kept, so that the numbers that are gone are only the purged ones
      t.bigint :tool_id, null: false
      t.string :kind, null: false
      t.bigint :record_id
      t.bigint :user_id
      t.bigint :access_token_id
      t.string :via
      t.boolean :agent, null: false, default: false
      t.json :data, null: false, default: {}
      t.datetime :created_at, null: false

      t.index %i[tool_id id]
      t.index :created_at
    end
  end
end
