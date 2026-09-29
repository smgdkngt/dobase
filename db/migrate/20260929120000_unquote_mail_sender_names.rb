# frozen_string_literal: true

# Sender names were saved as some servers write them in the header, in quotes and with
# their specials escaped ("Ann Example \\(Acme\\)"); Mails::IncomingMessage unquotes them now
class UnquoteMailSenderNames < ActiveRecord::Migration[8.1]
  class Message < ActiveRecord::Base
    self.table_name = "mail_messages"
  end

  def up
    Message.where("from_name LIKE ?", '"%"').find_each do |message|
      name = message.from_name.strip[1..-2].gsub(/\\+(.)/m, '\1').strip
      message.update_columns(from_name: name)
    end
  end

  def down
  end
end
