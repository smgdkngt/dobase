# frozen_string_literal: true

class AddDarkThemeToUsers < ActiveRecord::Migration[8.1]
  def change
    # One theme whatever the system says, or one for when it is light (theme_name) and
    # one for when it is dark (dark_theme_name; nil is the app's own dark look)
    add_column :users, :theme_follows_system, :boolean, null: false, default: false
    add_column :users, :dark_theme_name, :string
  end
end
