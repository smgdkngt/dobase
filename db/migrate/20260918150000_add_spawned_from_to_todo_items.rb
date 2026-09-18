# frozen_string_literal: true

class AddSpawnedFromToTodoItems < ActiveRecord::Migration[8.1]
  def change
    add_column :todo_items, :spawned_from_id, :integer
    add_index :todo_items, :spawned_from_id
  end
end
