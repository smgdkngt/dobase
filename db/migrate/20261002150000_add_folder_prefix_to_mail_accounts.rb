# frozen_string_literal: true

class AddFolderPrefixToMailAccounts < ActiveRecord::Migration[8.1]
  def change
    # What the mail server puts in front of every folder ("INBOX." where folders live inside
    # the inbox), learned on the next sync; nil until then and empty for a server without one
    add_column :mail_accounts, :folder_prefix, :string
  end
end
