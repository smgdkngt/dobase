class AddRecurrenceRuleToTodoItems < ActiveRecord::Migration[8.1]
  def change
    add_column :todo_items, :recurrence_rule, :string
  end
end
