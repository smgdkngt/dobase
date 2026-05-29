class AddMutedAtToCollaborators < ActiveRecord::Migration[8.1]
  def change
    add_column :collaborators, :muted_at, :datetime
  end
end
