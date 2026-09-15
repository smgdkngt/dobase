# frozen_string_literal: true

class AddAttendeesJsonToCalendarInvites < ActiveRecord::Migration[8.1]
  def change
    add_column :calendar_invites, :attendees_json, :text
  end
end
