# frozen_string_literal: true

# OAuth's device flow (RFC 8628), for `dobase login`: the CLI shows a short
# code, the person confirms it in any browser, and the CLI's polling then gets
# its tokens. No browser is needed on the machine the CLI runs on.
class CreateOauthDeviceCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_device_codes do |t|
      t.string :device_code_digest, null: false, index: { unique: true }
      t.string :user_code, null: false, index: { unique: true }
      t.references :oauth_client, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, foreign_key: { on_delete: :cascade }
      t.string :permission, null: false, default: "write"
      t.boolean :agent, null: false, default: false
      t.string :status, null: false, default: "pending"
      t.datetime :expires_at, null: false
      t.datetime :polled_at
      t.timestamps
    end

    # A login by code (the CLI on a machine) lasts thirty days from when it was
    # last used; a connection Claude made, thirty days from consent
    add_column :access_tokens, :renews, :boolean, null: false, default: false
  end
end
