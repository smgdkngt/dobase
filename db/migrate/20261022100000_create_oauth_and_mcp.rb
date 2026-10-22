# frozen_string_literal: true

# Connections from MCP clients (Claude, the dobase CLI) by OAuth 2.1. A consent
# makes an access token (`access_tokens`, as a personal token is), which is the
# connection: it is listed, named and revoked as one. The short-lived pairs an
# OAuth client actually sends are `oauth_grants` of that token.
class CreateOauthAndMcp < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_clients do |t|
      t.string :uid, null: false, index: { unique: true }
      t.string :name, null: false
      t.json :redirect_uris, null: false, default: []
      t.datetime :last_used_at
      t.timestamps
    end

    change_table :access_tokens do |t|
      t.references :oauth_client, foreign_key: { on_delete: :cascade }
      # The end of the connection, however often it is refreshed: thirty days after consent
      t.datetime :expires_at
    end

    create_table :oauth_authorization_codes do |t|
      t.string :code_digest, null: false, index: { unique: true }
      t.references :oauth_client, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :redirect_uri, null: false
      t.string :code_challenge, null: false
      t.string :permission, null: false, default: "read"
      t.boolean :agent, null: false, default: true
      t.datetime :expires_at, null: false
      t.datetime :used_at
      # The connection the code was exchanged for, revoked when the code comes back
      t.references :access_token, foreign_key: { on_delete: :nullify }
      t.timestamps
    end

    create_table :oauth_grants do |t|
      t.references :access_token, null: false, foreign_key: { on_delete: :cascade }
      t.string :token_digest, null: false, index: { unique: true }
      t.string :refresh_token_digest, null: false, index: { unique: true }
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.timestamps
    end

    create_table :mcp_tool_calls do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :access_token, foreign_key: { on_delete: :nullify }
      t.string :tool, null: false
      t.json :arguments, null: false, default: {}
      t.string :outcome, null: false
      t.string :error
      t.integer :duration_ms
      t.datetime :created_at, null: false
      t.index %i[user_id created_at]
    end

    add_column :users, :mcp_enabled, :boolean, null: false, default: true
  end
end
