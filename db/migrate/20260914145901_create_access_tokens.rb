class CreateAccessTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :access_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :permission, null: false, default: "read"
      t.string :token_digest, null: false, index: { unique: true }
      t.datetime :last_used_at
      t.timestamps
    end
  end
end
