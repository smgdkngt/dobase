# frozen_string_literal: true

# Collapsing a board column lived on the column itself, so folding a column out
# of the way folded it for everyone sharing the board. Whether a column is
# collapsed is personal, so it moves to a row per person per column.
class MoveColumnCollapseToColumnCollapses < ActiveRecord::Migration[8.1]
  def up
    create_table :column_collapses do |t|
      t.references :column, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :column_collapses, [ :column_id, :user_id ], unique: true

    # Nobody's board changes on deploy: a column that is collapsed today starts
    # out collapsed for every collaborator of the tool it belongs to.
    execute <<~SQL.squish
      INSERT INTO column_collapses (column_id, user_id, created_at, updated_at)
      SELECT columns.id, collaborators.user_id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM columns
      JOIN boards ON boards.id = columns.board_id
      JOIN collaborators ON collaborators.tool_id = boards.tool_id
      WHERE columns.collapsed
    SQL

    remove_column :columns, :collapsed
  end

  # Going back can only keep one state per column, so a column anybody had
  # collapsed comes back collapsed for all of them.
  def down
    add_column :columns, :collapsed, :boolean, default: false, null: false

    execute <<~SQL.squish
      UPDATE columns SET collapsed = TRUE
      WHERE id IN (SELECT column_id FROM column_collapses)
    SQL

    drop_table :column_collapses
  end
end
