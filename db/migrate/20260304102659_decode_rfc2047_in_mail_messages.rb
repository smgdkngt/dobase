# frozen_string_literal: true

class DecodeRfc2047InMailMessages < ActiveRecord::Migration[8.0]
  def up
    Mails::Message.where("subject LIKE '%=?%?=%' OR from_name LIKE '%=?%?=%'").find_each do |msg|
      updates = {}
      if msg.subject&.match?(/=\?[^?]+\?[BQbq]\?[^?]+\?=/)
        updates[:subject] = Mail::Encodings.value_decode(msg.subject)
      end
      if msg.from_name&.match?(/=\?[^?]+\?[BQbq]\?[^?]+\?=/)
        updates[:from_name] = Mail::Encodings.value_decode(msg.from_name)
      end
      msg.update_columns(updates) if updates.any?
    end
  end

  def down
    # Cannot reverse decoding
  end
end
