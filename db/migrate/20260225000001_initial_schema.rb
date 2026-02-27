# frozen_string_literal: true

class InitialSchema < ActiveRecord::Migration[8.1]
  def change
    create_table "users" do |t|
      t.string "first_name", null: false
      t.string "last_name", null: false
      t.string "email_address", null: false
      t.string "password_digest", null: false
      t.string "last_visited_path"
      t.string "timezone", default: "UTC"
      t.string "otp_secret"
      t.boolean "otp_required", default: false, null: false
      t.text "otp_recovery_codes"
      t.timestamps
      t.index [ "email_address" ], unique: true
    end

    create_table "sessions" do |t|
      t.belongs_to "user", null: false, foreign_key: true
      t.string "ip_address"
      t.string "user_agent"
      t.timestamps
    end

    create_table "tool_types" do |t|
      t.string "name", null: false
      t.string "slug", null: false
      t.string "icon", null: false
      t.text "description"
      t.boolean "enabled", default: true, null: false
      t.timestamps
      t.index [ "slug" ], unique: true
    end

    create_table "tools" do |t|
      t.string "name", null: false
      t.string "custom_icon"
      t.integer "sidebar_position", default: 0, null: false
      t.belongs_to "owner", null: false, foreign_key: { to_table: :users }
      t.belongs_to "tool_type", null: false, foreign_key: true
      t.timestamps
      t.index [ "owner_id", "tool_type_id" ]
    end

    create_table "collaborators" do |t|
      t.belongs_to "tool", null: false, foreign_key: true
      t.belongs_to "user", null: false, foreign_key: true
      t.string "role", default: "collaborator", null: false
      t.timestamps
      t.index [ "tool_id", "user_id" ], unique: true
    end

    create_table "invitations" do |t|
      t.belongs_to "tool", null: false, foreign_key: true
      t.belongs_to "invited_by", null: false, foreign_key: { to_table: :users }
      t.string "email", null: false
      t.string "token", null: false
      t.string "status", default: "pending", null: false
      t.datetime "expires_at", null: false
      t.datetime "accepted_at"
      t.timestamps
      t.index [ "token" ], unique: true
      t.index [ "tool_id", "email" ], name: "idx_invitations_pending", unique: true, where: "status = 'pending'"
    end

    create_table "sidebar_groups" do |t|
      t.belongs_to "user", null: false, foreign_key: true
      t.string "name", null: false
      t.integer "position", default: 0, null: false
      t.boolean "collapsed", default: false, null: false
      t.timestamps
      t.index [ "user_id", "position" ]
    end

    create_table "sidebar_memberships" do |t|
      t.belongs_to "sidebar_group", null: false, foreign_key: true
      t.belongs_to "tool", null: false, foreign_key: true
      t.integer "position", default: 0, null: false
      t.timestamps
      t.index [ "sidebar_group_id", "position" ]
      t.index [ "sidebar_group_id", "tool_id" ], name: "idx_sidebar_memberships_unique", unique: true
    end

    # Board tool
    create_table "boards" do |t|
      t.belongs_to "tool", null: false, foreign_key: true, index: { unique: true }
      t.timestamps
    end

    create_table "columns" do |t|
      t.belongs_to "board", null: false, foreign_key: true
      t.string "name", null: false
      t.integer "position", default: 0, null: false
      t.boolean "collapsed", default: false, null: false
      t.timestamps
      t.index [ "board_id", "position" ]
    end

    create_table "cards" do |t|
      t.belongs_to "column", null: false, foreign_key: true
      t.references "assigned_user", foreign_key: { to_table: :users }
      t.string "title", null: false
      t.text "description"
      t.string "color"
      t.date "due_date"
      t.integer "position", default: 0, null: false
      t.datetime "archived_at"
      t.timestamps
      t.index [ "column_id", "position" ]
    end

    create_table "comments" do |t|
      t.belongs_to "card", null: false, foreign_key: true
      t.belongs_to "user", null: false, foreign_key: true
      t.timestamps
    end

    create_table "card_attachments" do |t|
      t.belongs_to "card", null: false, foreign_key: true
      t.string "filename", null: false
      t.string "content_type"
      t.integer "file_size"
      t.timestamps
    end

    # Chat tool
    create_table "chats" do |t|
      t.belongs_to "tool", null: false, foreign_key: true, index: { unique: true }
      t.timestamps
    end

    create_table "chat_messages" do |t|
      t.belongs_to "chat", null: false, foreign_key: true
      t.belongs_to "user", null: false, foreign_key: true
      t.references "reply_to", foreign_key: { to_table: :chat_messages }
      t.datetime "edited_at"
      t.timestamps
      t.index [ "chat_id", "created_at" ]
    end

    create_table "chat_read_receipts" do |t|
      t.belongs_to "chat", null: false, foreign_key: true
      t.belongs_to "user", null: false, foreign_key: true
      t.references "last_read_message", foreign_key: { to_table: :chat_messages }
      t.datetime "last_read_at", null: false
      t.timestamps
      t.index [ "chat_id", "user_id" ], unique: true
    end

    # Docs tool
    create_table "documents" do |t|
      t.belongs_to "tool", null: false, foreign_key: true
      t.references "last_edited_by", foreign_key: { to_table: :users }
      t.references "locked_by", foreign_key: { to_table: :users, on_delete: :nullify }
      t.string "title", default: "Untitled", null: false
      t.text "content_html"
      t.text "content_json"
      t.integer "word_count", default: 0, null: false
      t.datetime "last_edited_at"
      t.datetime "locked_at"
      t.timestamps
      t.index [ "tool_id", "updated_at" ]
    end

    # Mail tool
    create_table "mail_accounts" do |t|
      t.belongs_to "tool", null: false, foreign_key: true, index: { unique: true }
      t.string "email_address", null: false
      t.string "username", null: false
      t.text "encrypted_password", null: false
      t.string "display_name"
      t.text "signature"
      t.string "imap_host", null: false
      t.integer "imap_port", default: 993
      t.boolean "imap_ssl", default: true
      t.string "smtp_host", null: false
      t.integer "smtp_port", default: 587
      t.boolean "smtp_tls", default: true
      t.string "smtp_auth", default: "plain"
      t.integer "auto_refresh_interval"
      t.text "synced_folders"
      t.string "sync_status", default: "pending"
      t.text "sync_error"
      t.datetime "last_synced_at"
      t.timestamps
    end

    create_table "mail_messages" do |t|
      t.belongs_to "mail_account", null: false, foreign_key: true
      t.string "message_id", null: false
      t.string "thread_id"
      t.string "subject"
      t.string "from_name"
      t.string "from_address"
      t.text "to_addresses"
      t.text "cc_addresses"
      t.text "body_plain"
      t.text "body_html"
      t.string "folder", default: "INBOX"
      t.string "in_reply_to"
      t.text "references"
      t.integer "uid"
      t.boolean "read", default: false
      t.boolean "starred", default: false
      t.boolean "archived", default: false, null: false
      t.boolean "trashed", default: false, null: false
      t.boolean "draft", default: false
      t.boolean "has_attachments", default: false, null: false
      t.datetime "sent_at"
      t.timestamps
      t.index [ "mail_account_id", "message_id" ], unique: true
      t.index [ "mail_account_id", "folder", "sent_at" ]
      t.index [ "mail_account_id", "thread_id" ]
      t.index [ "mail_account_id", "read" ]
      t.index [ "mail_account_id", "archived" ]
    end

    create_table "mail_attachments" do |t|
      t.belongs_to "mail_message", null: false, foreign_key: true
      t.string "filename", null: false
      t.string "content_type"
      t.integer "file_size"
      t.timestamps
    end

    create_table "mail_contacts" do |t|
      t.belongs_to "mail_account", null: false, foreign_key: true
      t.string "email_address", null: false
      t.string "name"
      t.integer "times_contacted", default: 0, null: false
      t.datetime "last_contacted_at"
      t.timestamps
      t.index [ "mail_account_id", "email_address" ], unique: true
      t.index [ "mail_account_id", "times_contacted" ], name: "index_email_contacts_on_account_and_frequency"
    end

    create_table "mail_labels" do |t|
      t.belongs_to "mail_account", null: false, foreign_key: true
      t.string "name", null: false
      t.string "color"
      t.timestamps
      t.index [ "mail_account_id", "name" ], unique: true
    end

    create_table "mail_label_assignments" do |t|
      t.belongs_to "mail_label", null: false, foreign_key: true
      t.belongs_to "mail_message", null: false, foreign_key: true
      t.timestamps
      t.index [ "mail_message_id", "mail_label_id" ], unique: true
    end

    # Files tool
    create_table "file_folders" do |t|
      t.belongs_to "tool", null: false, foreign_key: true
      t.references "parent", foreign_key: { to_table: :file_folders }
      t.string "name", null: false
      t.integer "position", default: 0, null: false
      t.integer "depth", default: 0, null: false
      t.timestamps
      t.index [ "tool_id", "parent_id", "position" ]
    end

    create_table "file_items" do |t|
      t.belongs_to "tool", null: false, foreign_key: true
      t.references "folder", foreign_key: { to_table: :file_folders }
      t.string "name", null: false
      t.string "content_type"
      t.bigint "file_size"
      t.integer "position", default: 0, null: false
      t.timestamps
      t.index [ "tool_id", "folder_id", "position" ]
    end

    create_table "file_shares" do |t|
      t.references "shareable", null: false, polymorphic: true
      t.belongs_to "created_by", null: false, foreign_key: { to_table: :users }
      t.string "token", null: false
      t.string "password_digest"
      t.integer "download_count", default: 0, null: false
      t.datetime "expires_at"
      t.timestamps
      t.index [ "token" ], unique: true
      t.index [ "expires_at" ]
    end

    # Calendar tool
    create_table "calendar_accounts" do |t|
      t.belongs_to "tool", null: false, foreign_key: true, index: { unique: true }
      t.string "username", null: false
      t.text "encrypted_password", null: false
      t.string "display_name"
      t.string "provider"
      t.string "caldav_url"
      t.string "principal_url"
      t.string "calendar_home_set_url"
      t.string "sync_status", default: "pending"
      t.text "sync_error"
      t.datetime "last_synced_at"
      t.timestamps
    end

    create_table "calendar_calendars" do |t|
      t.belongs_to "calendar_account", null: false, foreign_key: true
      t.string "remote_id", null: false
      t.string "remote_url"
      t.string "name", null: false
      t.string "color"
      t.string "description"
      t.string "ctag"
      t.string "sync_token"
      t.boolean "enabled", default: true
      t.boolean "is_default", default: false
      t.integer "position", default: 0
      t.timestamps
      t.index [ "calendar_account_id", "remote_id" ], unique: true
    end

    create_table "calendar_events" do |t|
      t.belongs_to "calendar", null: false, foreign_key: { to_table: :calendar_calendars }
      t.string "uid"
      t.string "summary", null: false
      t.text "description"
      t.string "location"
      t.datetime "starts_at", null: false
      t.datetime "ends_at", null: false
      t.boolean "all_day", default: false
      t.string "status", default: "confirmed"
      t.string "timezone"
      t.string "organizer_name"
      t.string "organizer_email"
      t.text "attendees_json"
      t.string "rrule"
      t.text "recurrence_schedule"
      t.string "recurrence_id"
      t.boolean "is_recurring", default: false
      t.string "etag"
      t.string "remote_href"
      t.text "raw_icalendar"
      t.timestamps
      t.index [ "calendar_id", "uid" ]
      t.index [ "calendar_id", "starts_at" ]
      t.index [ "calendar_id", "ends_at" ]
    end

    create_table "calendar_invites" do |t|
      t.belongs_to "mail_message", null: false, foreign_key: true
      t.references "added_to_calendar", foreign_key: { to_table: :calendar_calendars }
      t.references "created_event", foreign_key: { to_table: :calendar_events }
      t.string "uid", null: false
      t.string "summary"
      t.text "description"
      t.string "location"
      t.datetime "starts_at"
      t.datetime "ends_at"
      t.boolean "all_day", default: false
      t.string "organizer_name"
      t.string "organizer_email"
      t.string "method"
      t.string "status", default: "pending"
      t.text "raw_icalendar"
      t.timestamps
      t.index [ "mail_message_id", "uid" ], unique: true
    end

    # Room tool
    create_table "rooms" do |t|
      t.integer "tool_id", null: false
      t.timestamps
      t.index [ "tool_id" ], unique: true
    end
    add_foreign_key "rooms", "tools"

    # Todos tool
    create_table "todo_lists" do |t|
      t.integer "tool_id", null: false
      t.string "title", null: false
      t.text "description"
      t.integer "position", default: 0, null: false
      t.timestamps
      t.index [ "tool_id" ]
      t.index [ "tool_id", "position" ]
    end
    add_foreign_key "todo_lists", "tools"

    create_table "todo_items" do |t|
      t.integer "todo_list_id", null: false
      t.integer "assigned_user_id"
      t.string "title", null: false
      t.text "description"
      t.date "due_date"
      t.integer "position", default: 0, null: false
      t.datetime "completed_at"
      t.timestamps
      t.index [ "todo_list_id" ]
      t.index [ "todo_list_id", "position" ]
      t.index [ "assigned_user_id" ]
      t.index [ "completed_at" ]
    end
    add_foreign_key "todo_items", "todo_lists"
    add_foreign_key "todo_items", "users", column: "assigned_user_id"

    create_table "todo_comments" do |t|
      t.integer "todo_item_id", null: false
      t.integer "user_id", null: false
      t.timestamps
      t.index [ "todo_item_id" ]
      t.index [ "user_id" ]
    end
    add_foreign_key "todo_comments", "todo_items"
    add_foreign_key "todo_comments", "users"

    create_table "todo_item_attachments" do |t|
      t.integer "todo_item_id", null: false
      t.string "filename", null: false
      t.string "content_type"
      t.integer "file_size"
      t.timestamps
      t.index [ "todo_item_id" ]
    end
    add_foreign_key "todo_item_attachments", "todo_items"

    # Notifications (Noticed)
    create_table "noticed_events" do |t|
      t.string "type"
      t.json "params"
      t.references "record", polymorphic: true
      t.integer "notifications_count"
      t.timestamps
    end

    create_table "noticed_notifications" do |t|
      t.belongs_to "event", null: false, foreign_key: { to_table: :noticed_events }
      t.references "recipient", null: false, polymorphic: true
      t.string "type"
      t.datetime "read_at", precision: nil
      t.datetime "seen_at", precision: nil
      t.timestamps
    end

    # Action Text
    create_table "action_text_rich_texts" do |t|
      t.string "name", null: false
      t.text "body"
      t.references "record", null: false, polymorphic: true
      t.timestamps
      t.index [ "record_type", "record_id", "name" ], name: "index_action_text_rich_texts_uniqueness", unique: true
    end

    # Active Storage
    create_table "active_storage_blobs" do |t|
      t.string "key", null: false
      t.string "filename", null: false
      t.string "content_type"
      t.text "metadata"
      t.string "service_name", null: false
      t.bigint "byte_size", null: false
      t.string "checksum"
      t.datetime "created_at", null: false
      t.index [ "key" ], unique: true
    end

    create_table "active_storage_attachments" do |t|
      t.string "name", null: false
      t.references "record", null: false, polymorphic: true
      t.belongs_to "blob", null: false, foreign_key: { to_table: :active_storage_blobs }
      t.datetime "created_at", null: false
      t.index [ "record_type", "record_id", "name", "blob_id" ], name: "index_active_storage_attachments_uniqueness", unique: true
    end

    create_table "active_storage_variant_records" do |t|
      t.belongs_to "blob", null: false, foreign_key: { to_table: :active_storage_blobs }
      t.string "variation_digest", null: false
      t.index [ "blob_id", "variation_digest" ], name: "index_active_storage_variant_records_uniqueness", unique: true
    end
  end
end
