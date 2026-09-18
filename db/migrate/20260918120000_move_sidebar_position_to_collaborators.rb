# frozen_string_literal: true

# The order of the tools in the sidebar lived on the tool itself, so dragging a
# tool around your own sidebar reordered it for everyone you share it with. The
# order is personal, so it moves to the row that already ties a person to a
# tool: their collaborator record.
class MoveSidebarPositionToCollaborators < ActiveRecord::Migration[8.1]
  def up
    add_column :collaborators, :sidebar_position, :integer, default: 0, null: false
    add_index :collaborators, [ :user_id, :sidebar_position ]

    # Everybody starts from the shared order they see today.
    execute <<~SQL.squish
      UPDATE collaborators
      SET sidebar_position = (SELECT sidebar_position FROM tools WHERE tools.id = collaborators.tool_id)
    SQL

    remove_column :tools, :sidebar_position
  end

  # Going back can only keep one order per tool, so it keeps the owner's.
  # Everybody else's is lost, which is what a single shared column means.
  def down
    add_column :tools, :sidebar_position, :integer, default: 0, null: false

    execute <<~SQL.squish
      UPDATE tools
      SET sidebar_position = COALESCE((
        SELECT sidebar_position FROM collaborators
        WHERE collaborators.tool_id = tools.id AND collaborators.user_id = tools.owner_id
      ), 0)
    SQL

    remove_index :collaborators, [ :user_id, :sidebar_position ]
    remove_column :collaborators, :sidebar_position
  end
end
