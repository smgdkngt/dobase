# frozen_string_literal: true

class CreateWorkspaceLayouts < ActiveRecord::Migration[8.1]
  def change
    # Which tiles someone has open, where, and on which desktop: one arrangement per
    # person, the same in every browser they use. Each change is one revision on.
    create_table :workspace_layouts do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.json :state, null: false, default: {}
      t.integer :revision, null: false, default: 0
      t.timestamps
    end
  end
end
