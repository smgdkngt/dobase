# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_04_24_053342) do
  create_table "action_text_rich_texts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "boards", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "tool_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tool_id"], name: "index_boards_on_tool_id", unique: true
  end

  create_table "calendar_accounts", force: :cascade do |t|
    t.string "caldav_url"
    t.string "calendar_home_set_url"
    t.datetime "created_at", null: false
    t.string "display_name"
    t.text "encrypted_password"
    t.datetime "last_synced_at"
    t.string "principal_url"
    t.string "provider"
    t.text "sync_error"
    t.string "sync_status", default: "pending"
    t.bigint "tool_id", null: false
    t.datetime "updated_at", null: false
    t.string "username"
    t.index ["tool_id"], name: "index_calendar_accounts_on_tool_id", unique: true
  end

  create_table "calendar_calendars", force: :cascade do |t|
    t.bigint "calendar_account_id", null: false
    t.string "color"
    t.datetime "created_at", null: false
    t.string "ctag"
    t.string "description"
    t.boolean "enabled", default: true
    t.boolean "is_default", default: false
    t.string "name", null: false
    t.integer "position", default: 0
    t.boolean "read_only", default: false, null: false
    t.string "remote_id", null: false
    t.string "remote_url"
    t.string "sync_token"
    t.datetime "updated_at", null: false
    t.index ["calendar_account_id", "remote_id"], name: "index_calendar_calendars_on_calendar_account_id_and_remote_id", unique: true
    t.index ["calendar_account_id"], name: "index_calendar_calendars_on_calendar_account_id"
  end

  create_table "calendar_events", force: :cascade do |t|
    t.boolean "all_day", default: false
    t.text "attendees_json"
    t.bigint "calendar_id", null: false
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.text "description"
    t.datetime "ends_at", null: false
    t.string "etag"
    t.boolean "is_recurring", default: false
    t.string "location"
    t.string "organizer_email"
    t.string "organizer_name"
    t.text "raw_icalendar"
    t.string "recurrence_id"
    t.text "recurrence_schedule"
    t.string "remote_href"
    t.string "rrule"
    t.datetime "starts_at", null: false
    t.string "status", default: "confirmed"
    t.string "summary", null: false
    t.string "timezone"
    t.string "uid"
    t.datetime "updated_at", null: false
    t.integer "updated_by_id"
    t.index ["calendar_id", "ends_at"], name: "index_calendar_events_on_calendar_id_and_ends_at"
    t.index ["calendar_id", "starts_at"], name: "index_calendar_events_on_calendar_id_and_starts_at"
    t.index ["calendar_id", "uid"], name: "index_calendar_events_on_calendar_id_and_uid"
    t.index ["calendar_id"], name: "index_calendar_events_on_calendar_id"
    t.index ["created_by_id"], name: "index_calendar_events_on_created_by_id"
    t.index ["updated_by_id"], name: "index_calendar_events_on_updated_by_id"
  end

  create_table "calendar_invites", force: :cascade do |t|
    t.bigint "added_to_calendar_id"
    t.boolean "all_day", default: false
    t.datetime "created_at", null: false
    t.bigint "created_event_id"
    t.string "description"
    t.datetime "ends_at"
    t.string "location"
    t.bigint "mail_message_id", null: false
    t.string "method"
    t.string "organizer_email"
    t.string "organizer_name"
    t.text "raw_icalendar"
    t.datetime "starts_at"
    t.string "status", default: "pending"
    t.string "summary"
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index ["added_to_calendar_id"], name: "index_calendar_invites_on_added_to_calendar_id"
    t.index ["created_event_id"], name: "index_calendar_invites_on_created_event_id"
    t.index ["mail_message_id", "uid"], name: "index_calendar_invites_on_mail_message_id_and_uid", unique: true
    t.index ["mail_message_id"], name: "index_calendar_invites_on_mail_message_id"
  end

  create_table "card_attachments", force: :cascade do |t|
    t.bigint "card_id", null: false
    t.string "content_type"
    t.datetime "created_at", null: false
    t.integer "file_size"
    t.string "filename", null: false
    t.datetime "updated_at", null: false
    t.index ["card_id"], name: "index_card_attachments_on_card_id"
  end

  create_table "cards", force: :cascade do |t|
    t.datetime "archived_at"
    t.bigint "assigned_user_id"
    t.string "color"
    t.bigint "column_id", null: false
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.text "description"
    t.date "due_date"
    t.integer "position", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "updated_by_id"
    t.index ["assigned_user_id"], name: "index_cards_on_assigned_user_id"
    t.index ["column_id", "position"], name: "index_cards_on_column_id_and_position"
    t.index ["column_id"], name: "index_cards_on_column_id"
    t.index ["created_by_id"], name: "index_cards_on_created_by_id"
    t.index ["updated_by_id"], name: "index_cards_on_updated_by_id"
  end

  create_table "chat_messages", force: :cascade do |t|
    t.bigint "chat_id", null: false
    t.datetime "created_at", null: false
    t.datetime "edited_at"
    t.bigint "reply_to_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["chat_id", "created_at"], name: "index_chat_messages_on_chat_id_and_created_at"
    t.index ["chat_id"], name: "index_chat_messages_on_chat_id"
    t.index ["reply_to_id"], name: "index_chat_messages_on_reply_to_id"
    t.index ["user_id"], name: "index_chat_messages_on_user_id"
  end

  create_table "chat_read_receipts", force: :cascade do |t|
    t.bigint "chat_id", null: false
    t.datetime "created_at", null: false
    t.datetime "last_read_at", null: false
    t.bigint "last_read_message_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["chat_id", "user_id"], name: "index_chat_read_receipts_on_chat_id_and_user_id", unique: true
    t.index ["chat_id"], name: "index_chat_read_receipts_on_chat_id"
    t.index ["last_read_message_id"], name: "index_chat_read_receipts_on_last_read_message_id"
    t.index ["user_id"], name: "index_chat_read_receipts_on_user_id"
  end

  create_table "chats", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "tool_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tool_id"], name: "index_chats_on_tool_id", unique: true
  end

  create_table "collaborators", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_seen_at"
    t.string "role", default: "collaborator", null: false
    t.bigint "tool_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["tool_id", "user_id"], name: "index_collaborators_on_tool_id_and_user_id", unique: true
    t.index ["tool_id"], name: "index_collaborators_on_tool_id"
    t.index ["user_id"], name: "index_collaborators_on_user_id"
  end

  create_table "columns", force: :cascade do |t|
    t.bigint "board_id", null: false
    t.boolean "collapsed", default: false, null: false
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "updated_by_id"
    t.index ["board_id", "position"], name: "index_columns_on_board_id_and_position"
    t.index ["board_id"], name: "index_columns_on_board_id"
    t.index ["created_by_id"], name: "index_columns_on_created_by_id"
    t.index ["updated_by_id"], name: "index_columns_on_updated_by_id"
  end

  create_table "comments", force: :cascade do |t|
    t.bigint "card_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["card_id"], name: "index_comments_on_card_id"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "documents", force: :cascade do |t|
    t.text "content_html"
    t.text "content_json"
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.datetime "last_edited_at"
    t.datetime "locked_at"
    t.bigint "locked_by_id"
    t.string "title", default: "Untitled", null: false
    t.bigint "tool_id", null: false
    t.datetime "updated_at", null: false
    t.integer "updated_by_id"
    t.integer "word_count", default: 0, null: false
    t.index ["created_by_id"], name: "index_documents_on_created_by_id"
    t.index ["locked_by_id"], name: "index_documents_on_locked_by_id"
    t.index ["tool_id", "updated_at"], name: "index_documents_on_tool_id_and_updated_at"
    t.index ["tool_id"], name: "index_documents_on_tool_id"
    t.index ["updated_by_id"], name: "index_documents_on_updated_by_id"
  end

  create_table "file_folders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.integer "depth", default: 0, null: false
    t.string "name", null: false
    t.bigint "parent_id"
    t.integer "position", default: 0, null: false
    t.bigint "tool_id", null: false
    t.datetime "updated_at", null: false
    t.integer "updated_by_id"
    t.index ["created_by_id"], name: "index_file_folders_on_created_by_id"
    t.index ["parent_id"], name: "index_file_folders_on_parent_id"
    t.index ["tool_id", "parent_id", "position"], name: "index_file_folders_on_tool_id_and_parent_id_and_position"
    t.index ["tool_id"], name: "index_file_folders_on_tool_id"
    t.index ["updated_by_id"], name: "index_file_folders_on_updated_by_id"
  end

  create_table "file_items", force: :cascade do |t|
    t.string "content_type"
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.bigint "file_size"
    t.bigint "folder_id"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.bigint "tool_id", null: false
    t.datetime "updated_at", null: false
    t.integer "updated_by_id"
    t.index ["created_by_id"], name: "index_file_items_on_created_by_id"
    t.index ["folder_id"], name: "index_file_items_on_folder_id"
    t.index ["tool_id", "folder_id", "position"], name: "index_file_items_on_tool_id_and_folder_id_and_position"
    t.index ["tool_id"], name: "index_file_items_on_tool_id"
    t.index ["updated_by_id"], name: "index_file_items_on_updated_by_id"
  end

  create_table "file_shares", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id", null: false
    t.integer "download_count", default: 0, null: false
    t.datetime "expires_at"
    t.string "password_digest"
    t.bigint "shareable_id", null: false
    t.string "shareable_type", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_file_shares_on_created_by_id"
    t.index ["expires_at"], name: "index_file_shares_on_expires_at"
    t.index ["shareable_type", "shareable_id"], name: "index_file_shares_on_shareable"
    t.index ["token"], name: "index_file_shares_on_token", unique: true
  end

  create_table "invitations", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "expires_at", null: false
    t.bigint "invited_by_id", null: false
    t.string "status", default: "pending", null: false
    t.string "token", null: false
    t.bigint "tool_id", null: false
    t.datetime "updated_at", null: false
    t.index ["invited_by_id"], name: "index_invitations_on_invited_by_id"
    t.index ["token"], name: "index_invitations_on_token", unique: true
    t.index ["tool_id", "email"], name: "idx_invitations_pending", unique: true, where: "status = 'pending'"
    t.index ["tool_id"], name: "index_invitations_on_tool_id"
  end

  create_table "mail_accounts", force: :cascade do |t|
    t.string "archive_folder"
    t.integer "auto_refresh_interval"
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "email_address", null: false
    t.text "encrypted_password", null: false
    t.string "imap_host", null: false
    t.integer "imap_port", default: 993
    t.boolean "imap_ssl", default: true
    t.datetime "last_synced_at"
    t.text "signature"
    t.string "smtp_auth", default: "plain"
    t.string "smtp_host", null: false
    t.integer "smtp_port", default: 587
    t.boolean "smtp_tls", default: true
    t.text "sync_error"
    t.string "sync_status", default: "pending"
    t.text "synced_folders"
    t.bigint "tool_id", null: false
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.index ["tool_id"], name: "index_mail_accounts_on_tool_id", unique: true
  end

  create_table "mail_attachments", force: :cascade do |t|
    t.string "content_type"
    t.datetime "created_at", null: false
    t.integer "file_size"
    t.string "filename", null: false
    t.bigint "mail_message_id", null: false
    t.datetime "updated_at", null: false
    t.index ["mail_message_id"], name: "index_mail_attachments_on_mail_message_id"
  end

  create_table "mail_contacts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.datetime "last_contacted_at"
    t.bigint "mail_account_id", null: false
    t.string "name"
    t.integer "times_contacted", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["mail_account_id", "email_address"], name: "index_mail_contacts_on_mail_account_id_and_email_address", unique: true
    t.index ["mail_account_id", "times_contacted"], name: "index_email_contacts_on_account_and_frequency"
    t.index ["mail_account_id"], name: "index_mail_contacts_on_mail_account_id"
  end

  create_table "mail_label_assignments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "mail_label_id", null: false
    t.bigint "mail_message_id", null: false
    t.datetime "updated_at", null: false
    t.index ["mail_label_id"], name: "index_mail_label_assignments_on_mail_label_id"
    t.index ["mail_message_id", "mail_label_id"], name: "idx_on_mail_message_id_mail_label_id_d5dc158252", unique: true
    t.index ["mail_message_id"], name: "index_mail_label_assignments_on_mail_message_id"
  end

  create_table "mail_labels", force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.bigint "mail_account_id", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["mail_account_id", "name"], name: "index_mail_labels_on_mail_account_id_and_name", unique: true
    t.index ["mail_account_id"], name: "index_mail_labels_on_mail_account_id"
  end

  create_table "mail_messages", force: :cascade do |t|
    t.boolean "archived", default: false, null: false
    t.text "body_html"
    t.text "body_plain"
    t.text "cc_addresses"
    t.datetime "created_at", null: false
    t.boolean "draft", default: false
    t.string "folder", default: "INBOX"
    t.string "from_address"
    t.string "from_name"
    t.boolean "has_attachments", default: false, null: false
    t.string "in_reply_to"
    t.bigint "mail_account_id", null: false
    t.string "message_id", null: false
    t.boolean "read", default: false
    t.text "references"
    t.datetime "sent_at"
    t.boolean "starred", default: false
    t.string "subject"
    t.string "thread_id"
    t.text "to_addresses"
    t.boolean "trashed", default: false, null: false
    t.integer "uid"
    t.datetime "updated_at", null: false
    t.index ["mail_account_id", "archived"], name: "index_mail_messages_on_mail_account_id_and_archived"
    t.index ["mail_account_id", "folder", "sent_at"], name: "index_mail_messages_on_mail_account_id_and_folder_and_sent_at"
    t.index ["mail_account_id", "message_id"], name: "index_mail_messages_on_mail_account_id_and_message_id", unique: true
    t.index ["mail_account_id", "read"], name: "index_mail_messages_on_mail_account_id_and_read"
    t.index ["mail_account_id", "thread_id"], name: "index_mail_messages_on_mail_account_id_and_thread_id"
    t.index ["mail_account_id"], name: "index_mail_messages_on_mail_account_id"
  end

  create_table "noticed_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "notifications_count"
    t.json "params"
    t.bigint "record_id"
    t.string "record_type"
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id"], name: "index_noticed_events_on_record"
  end

  create_table "noticed_notifications", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.datetime "read_at", precision: nil
    t.bigint "recipient_id", null: false
    t.string "recipient_type", null: false
    t.datetime "seen_at", precision: nil
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_noticed_notifications_on_event_id"
    t.index ["recipient_type", "recipient_id"], name: "index_noticed_notifications_on_recipient"
  end

  create_table "rooms", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "tool_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tool_id"], name: "index_rooms_on_tool_id", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "sidebar_groups", force: :cascade do |t|
    t.boolean "collapsed", default: false, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "position"], name: "index_sidebar_groups_on_user_id_and_position"
    t.index ["user_id"], name: "index_sidebar_groups_on_user_id"
  end

  create_table "sidebar_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "position", default: 0, null: false
    t.bigint "sidebar_group_id", null: false
    t.bigint "tool_id", null: false
    t.datetime "updated_at", null: false
    t.index ["sidebar_group_id", "position"], name: "index_sidebar_memberships_on_sidebar_group_id_and_position"
    t.index ["sidebar_group_id", "tool_id"], name: "idx_sidebar_memberships_unique", unique: true
    t.index ["sidebar_group_id"], name: "index_sidebar_memberships_on_sidebar_group_id"
    t.index ["tool_id"], name: "index_sidebar_memberships_on_tool_id"
  end

  create_table "todo_comments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "todo_item_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["todo_item_id"], name: "index_todo_comments_on_todo_item_id"
    t.index ["user_id"], name: "index_todo_comments_on_user_id"
  end

  create_table "todo_item_attachments", force: :cascade do |t|
    t.string "content_type"
    t.datetime "created_at", null: false
    t.integer "file_size"
    t.string "filename", null: false
    t.integer "todo_item_id", null: false
    t.datetime "updated_at", null: false
    t.index ["todo_item_id"], name: "index_todo_item_attachments_on_todo_item_id"
  end

  create_table "todo_items", force: :cascade do |t|
    t.integer "assigned_user_id"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.text "description"
    t.date "due_date"
    t.integer "position", default: 0, null: false
    t.string "title", null: false
    t.integer "todo_list_id", null: false
    t.datetime "updated_at", null: false
    t.integer "updated_by_id"
    t.index ["assigned_user_id"], name: "index_todo_items_on_assigned_user_id"
    t.index ["completed_at"], name: "index_todo_items_on_completed_at"
    t.index ["created_by_id"], name: "index_todo_items_on_created_by_id"
    t.index ["todo_list_id", "position"], name: "index_todo_items_on_todo_list_id_and_position"
    t.index ["todo_list_id"], name: "index_todo_items_on_todo_list_id"
    t.index ["updated_by_id"], name: "index_todo_items_on_updated_by_id"
  end

  create_table "todo_lists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.text "description"
    t.integer "position", default: 0, null: false
    t.string "title", null: false
    t.integer "tool_id", null: false
    t.datetime "updated_at", null: false
    t.integer "updated_by_id"
    t.index ["created_by_id"], name: "index_todo_lists_on_created_by_id"
    t.index ["tool_id", "position"], name: "index_todo_lists_on_tool_id_and_position"
    t.index ["tool_id"], name: "index_todo_lists_on_tool_id"
    t.index ["updated_by_id"], name: "index_todo_lists_on_updated_by_id"
  end

  create_table "tool_types", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.string "icon", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_tool_types_on_slug", unique: true
  end

  create_table "tools", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "custom_icon"
    t.string "name", null: false
    t.bigint "owner_id", null: false
    t.integer "sidebar_position", default: 0, null: false
    t.bigint "tool_type_id", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id", "tool_type_id"], name: "index_tools_on_owner_id_and_tool_type_id"
    t.index ["owner_id"], name: "index_tools_on_owner_id"
    t.index ["tool_type_id"], name: "index_tools_on_tool_type_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.datetime "last_notification_digest_at"
    t.string "last_visited_path"
    t.string "notification_digest", default: "daily", null: false
    t.text "otp_recovery_codes"
    t.boolean "otp_required", default: false, null: false
    t.string "otp_secret"
    t.string "password_digest", null: false
    t.string "timezone", default: "UTC"
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "boards", "tools"
  add_foreign_key "calendar_accounts", "tools"
  add_foreign_key "calendar_calendars", "calendar_accounts"
  add_foreign_key "calendar_events", "calendar_calendars", column: "calendar_id"
  add_foreign_key "calendar_events", "users", column: "created_by_id"
  add_foreign_key "calendar_events", "users", column: "updated_by_id"
  add_foreign_key "calendar_invites", "calendar_calendars", column: "added_to_calendar_id"
  add_foreign_key "calendar_invites", "calendar_events", column: "created_event_id"
  add_foreign_key "calendar_invites", "mail_messages"
  add_foreign_key "card_attachments", "cards"
  add_foreign_key "cards", "columns"
  add_foreign_key "cards", "users", column: "assigned_user_id"
  add_foreign_key "cards", "users", column: "created_by_id"
  add_foreign_key "cards", "users", column: "updated_by_id"
  add_foreign_key "chat_messages", "chat_messages", column: "reply_to_id"
  add_foreign_key "chat_messages", "chats"
  add_foreign_key "chat_messages", "users"
  add_foreign_key "chat_read_receipts", "chat_messages", column: "last_read_message_id"
  add_foreign_key "chat_read_receipts", "chats"
  add_foreign_key "chat_read_receipts", "users"
  add_foreign_key "chats", "tools"
  add_foreign_key "collaborators", "tools"
  add_foreign_key "collaborators", "users"
  add_foreign_key "columns", "boards"
  add_foreign_key "columns", "users", column: "created_by_id"
  add_foreign_key "columns", "users", column: "updated_by_id"
  add_foreign_key "comments", "cards"
  add_foreign_key "comments", "users"
  add_foreign_key "documents", "tools"
  add_foreign_key "documents", "users", column: "created_by_id"
  add_foreign_key "documents", "users", column: "locked_by_id", on_delete: :nullify
  add_foreign_key "documents", "users", column: "updated_by_id"
  add_foreign_key "file_folders", "file_folders", column: "parent_id"
  add_foreign_key "file_folders", "tools"
  add_foreign_key "file_folders", "users", column: "created_by_id"
  add_foreign_key "file_folders", "users", column: "updated_by_id"
  add_foreign_key "file_items", "file_folders", column: "folder_id"
  add_foreign_key "file_items", "tools"
  add_foreign_key "file_items", "users", column: "created_by_id"
  add_foreign_key "file_items", "users", column: "updated_by_id"
  add_foreign_key "file_shares", "users", column: "created_by_id"
  add_foreign_key "invitations", "tools"
  add_foreign_key "invitations", "users", column: "invited_by_id"
  add_foreign_key "mail_accounts", "tools"
  add_foreign_key "mail_attachments", "mail_messages"
  add_foreign_key "mail_contacts", "mail_accounts"
  add_foreign_key "mail_label_assignments", "mail_labels"
  add_foreign_key "mail_label_assignments", "mail_messages"
  add_foreign_key "mail_labels", "mail_accounts"
  add_foreign_key "mail_messages", "mail_accounts"
  add_foreign_key "rooms", "tools"
  add_foreign_key "sessions", "users"
  add_foreign_key "sidebar_groups", "users"
  add_foreign_key "sidebar_memberships", "sidebar_groups"
  add_foreign_key "sidebar_memberships", "tools"
  add_foreign_key "todo_comments", "todo_items"
  add_foreign_key "todo_comments", "users"
  add_foreign_key "todo_item_attachments", "todo_items"
  add_foreign_key "todo_items", "todo_lists"
  add_foreign_key "todo_items", "users", column: "assigned_user_id"
  add_foreign_key "todo_items", "users", column: "created_by_id"
  add_foreign_key "todo_items", "users", column: "updated_by_id"
  add_foreign_key "todo_lists", "tools"
  add_foreign_key "todo_lists", "users", column: "created_by_id"
  add_foreign_key "todo_lists", "users", column: "updated_by_id"
  add_foreign_key "tools", "tool_types"
  add_foreign_key "tools", "users", column: "owner_id"
end
