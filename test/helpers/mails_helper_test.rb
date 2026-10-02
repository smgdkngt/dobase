# frozen_string_literal: true

require "test_helper"

class MailsHelperTest < ActionView::TestCase
  test "folders are shown as the server nests them, in alphabetical order" do
    folders = [ "Notes", "sem archive/Invoices", "DectDirect.nl", "sem archive", "Notes/Archive", "INBOX.Clients", "INBOX.Clients.Acme" ]

    assert_equal [
      [ "DectDirect.nl", "DectDirect.nl", 0 ],
      [ "INBOX.Clients", "INBOX.Clients", 0 ],
      [ "INBOX.Clients.Acme", "Acme", 1 ],
      [ "Notes", "Notes", 0 ],
      [ "Notes/Archive", "Archive", 1 ],
      [ "sem archive", "sem archive", 0 ],
      [ "sem archive/Invoices", "Invoices", 1 ]
    ], mail_folder_tree(folders).map { |folder| folder.values_at(:key, :label, :depth) }
  end

  test "folders the server keeps inside the inbox show by their own names" do
    account = mails_accounts(:primary)
    folders = [ "INBOX.Templates", "INBOX.blorpo", "INBOX.Clients.Acme", "INBOX.Clients", "INBOX.B&APw-ro" ]
    account.update!(folder_prefix: "INBOX.", synced_folders: [ "INBOX", "Sent", *folders ].to_json)
    @tool = account.tool

    assert_equal [
      [ "INBOX.blorpo", "blorpo", "blorpo", 0 ],
      [ "INBOX.B&APw-ro", "Büro", "Büro", 0 ],
      [ "INBOX.Clients", "Clients", "Clients", 0 ],
      [ "INBOX.Clients.Acme", "Acme", "Clients.Acme", 1 ],
      [ "INBOX.Templates", "Templates", "Templates", 0 ]
    ], mail_folder_tree(folders).map { |folder| folder.values_at(:key, :label, :name, :depth) }
  end

  # Servers name folders in modified UTF-7 (RFC 3501, 5.1.3): "&" is "&-", other letters are encoded

  test "a folder shows by the name it was given, and keeps the server's name as its key" do
    folders = [ "B&APw-ro", "Facturen &- bonnen", "Klanten", "Klanten/Caf&AOk-", "&AMk-cole" ]

    assert_equal [
      [ "B&APw-ro", "Büro", "Büro", 0 ],
      [ "&AMk-cole", "École", "École", 0 ],
      [ "Facturen &- bonnen", "Facturen & bonnen", "Facturen & bonnen", 0 ],
      [ "Klanten", "Klanten", "Klanten", 0 ],
      [ "Klanten/Caf&AOk-", "Café", "Klanten/Café", 1 ]
    ], mail_folder_tree(folders).map { |folder| folder.values_at(:key, :label, :name, :depth) }
  end

  test "a folder name that isn't modified UTF-7 shows as it is" do
    names = [ "Work (old)", "R&D", "Caf&AOk", "Büro", "Bad &AOk!-", "" ]

    assert_equal names, names.map { |name| mail_folder_name(name) }
    assert_equal "", mail_folder_name(nil)
  end
end
