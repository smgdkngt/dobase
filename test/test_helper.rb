ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require_relative "test_helpers/api_test_helper"
require_relative "test_helpers/demo_test_helper"
require_relative "test_helpers/fake_imap_server"
require_relative "test_helpers/mail_thread_helper"
require_relative "test_helpers/query_count_test_helper"
require_relative "test_helpers/smtp_test_helper"

# Tests never look up real host names. Names count as public servers, except
# "localhost" and "*.internal", which resolve like a machine's own and a private network's.
RemoteHost.resolver = ->(host) do
  case host
  when "localhost" then [ "127.0.0.1" ]
  when /\.internal\z/ then [ "10.1.2.3" ]
  when /\.invalid\z/ then []
  else [ "203.0.113.10" ]
  end
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Map fixture files to namespaced models
    set_fixture_class boards: Boards::Board
    set_fixture_class columns: Boards::Column
    set_fixture_class cards: Boards::Card
    set_fixture_class "calendars/accounts": Calendars::Account
    set_fixture_class "calendars/calendars": Calendars::Calendar
    set_fixture_class "calendars/events": Calendars::Event
    set_fixture_class file_folders: Files::Folder
    set_fixture_class file_items: Files::Item
    set_fixture_class file_shares: Files::Share
    set_fixture_class "mails/accounts": Mails::Account
    set_fixture_class "mails/messages": Mails::Message
    set_fixture_class rooms: Rooms::Room
    set_fixture_class todo_lists: Todos::List
    set_fixture_class todo_items: Todos::Item
    set_fixture_class todo_comments: Todos::Comment
    set_fixture_class todo_item_attachments: Todos::Attachment

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
