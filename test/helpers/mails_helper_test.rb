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
end
