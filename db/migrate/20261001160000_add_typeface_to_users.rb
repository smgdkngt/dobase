# frozen_string_literal: true

class AddTypefaceToUsers < ActiveRecord::Migration[8.1]
  def change
    # "mono" for the whole interface in the monospace font; nil for the app's own
    add_column :users, :typeface, :string
  end
end
