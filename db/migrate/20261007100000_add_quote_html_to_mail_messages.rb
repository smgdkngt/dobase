# frozen_string_literal: true

# The quote of a reply or forward as it was changed while writing (a part taken out of it).
# Empty, the quoted mail goes along as it was written.
class AddQuoteHtmlToMailMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :mail_messages, :quote_html, :text
  end
end
