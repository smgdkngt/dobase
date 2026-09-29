# frozen_string_literal: true

# The Content-ID of a picture in a mail, which its HTML shows with <img src="cid:...">
class AddContentIdToMailAttachments < ActiveRecord::Migration[8.1]
  def change
    add_column :mail_attachments, :content_id, :string
  end
end
