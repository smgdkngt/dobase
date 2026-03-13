class AddLastSeenAtToCollaborators < ActiveRecord::Migration[8.1]
  def change
    add_column :collaborators, :last_seen_at, :datetime
  end
end
