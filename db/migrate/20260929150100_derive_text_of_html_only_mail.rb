# frozen_string_literal: true

# A mail with only an HTML part had that HTML saved as its text too, so the list's
# preview showed markup. Its text is the HTML's text now, as Mails::IncomingMessage saves it.
class DeriveTextOfHtmlOnlyMail < ActiveRecord::Migration[8.1]
  class Message < ActiveRecord::Base
    self.table_name = "mail_messages"
  end

  def up
    Message.where("body_plain = body_html").find_each do |message|
      message.update_columns(body_plain: Mails::PlainText.from_html(message.body_html))
    end
  end

  def down
  end
end
