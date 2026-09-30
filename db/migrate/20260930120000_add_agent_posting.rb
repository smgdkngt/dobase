# frozen_string_literal: true

# An access token can post as an agent of its own (under the token's name, on
# behalf of its owner) instead of as its owner. Chat messages and comments keep
# which token posted them, and whether it did so as an agent.
class AddAgentPosting < ActiveRecord::Migration[8.1]
  def change
    add_column :access_tokens, :agent, :boolean, default: false, null: false

    %i[chat_messages comments todo_comments].each do |table|
      add_column table, :via, :string
      add_column table, :agent, :boolean, default: false, null: false
    end
  end
end
