# frozen_string_literal: true

class AddThemeToUsers < ActiveRecord::Migration[8.1]
  def change
    # The name of a built-in theme, or of the palette in theme_colors
    add_column :users, :theme_name, :string
    add_column :users, :theme_colors, :json
  end
end
