# frozen_string_literal: true

module MailThreadHelper
  # Two inbox messages in one conversation, with UIDs 201 and 202, oldest first
  def create_mail_thread(account = mails_accounts(:primary))
    [ 201, 202 ].map.with_index do |uid, index|
      account.messages.create!(message_id: "<lunch-#{uid}@example.com>", folder: "INBOX", uid: uid, subject: "Lunch?",
        from_address: "ann@example.com", to_addresses: "[]", sent_at: (2 - index).hours.ago, thread_id: "thread-lunch")
    end
  end

  # Six messages about one offsite, oldest first: the third and the fourth unread, each
  # answer carrying what it answers below it the way mail programs do (a plain-text one
  # with "> " lines, HTML ones as Gmail and Apple Mail write them)
  def create_long_conversation(account = mails_accounts(:primary))
    ann = { from_address: "ann@example.com", from_name: "Ann Lee", to_addresses: '["testuser@example.com"]' }
    me = { from_address: "testuser@example.com", from_name: "Test User", to_addresses: '["ann@example.com"]', cc_addresses: '["joe@example.com"]' }
    texts = [
      "Hi! Shall we pick a venue for the offsite? I found two places near the lake, both free in the second week of June.",
      "Sounds good. The one with the boathouse looks best to me; can you ask what they charge for a group of twenty?",
      "They came back to me: 45 euros a head for the day, lunch included. They can also do dinner on the terrace if we want to stay.",
      "One more thing: the boathouse has room for a workshop in the morning, with a projector. We would have it to ourselves until three.",
      "Great, let's stay for dinner. Could you book it for Thursday the 12th?",
      "Booked for Thursday the 12th, twenty people, with dinner. I'll send the address around next week."
    ]
    after = "The rest of my week is busy, so let me know by Friday whether that works for everyone, and if anyone needs a lift from the station I can drive two people."
    texts = texts.map { |text| "#{text}\n\n#{after}" }
    quoted = ""

    texts.each_with_index.map do |text, index|
      person = index.even? ? ann : me
      plain = quoted.empty? ? text : "#{text}\n\nOn Monday, Ann Lee wrote:\n#{quoted.lines.map { |line| "> #{line}" }.join}"
      html = if index == 3
        %(<div dir="ltr"><p>#{text.sub("\n\n", "</p><p>")}</p></div><div class="gmail_quote"><div class="gmail_attr">On Monday, Ann Lee wrote:</div><blockquote class="gmail_quote"><p>#{texts[2]}</p><blockquote><p>#{texts[1]}</p></blockquote></blockquote></div>)
      elsif index == 5
        %(<div><p>#{text.sub("\n\n", "</p><p>")}</p><p>Ann</p></div><div><br><blockquote type="cite"><div>On Tuesday, Test User wrote:</div><br><div><p>#{texts[4]}</p><blockquote type="cite"><p>#{texts[3]}</p><blockquote type="cite"><p>#{texts[2]}</p></blockquote></blockquote></div></blockquote></div>)
      end
      quoted = plain

      account.messages.create!(**person, message_id: "<offsite-#{index}@example.com>", folder: "INBOX", uid: 300 + index,
        subject: index.zero? ? "Venue for the offsite" : "Re: Venue for the offsite", body_plain: plain, body_html: html,
        read: ![ 2, 3 ].include?(index), sent_at: (6 - index).hours.ago, thread_id: "thread-offsite")
    end
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include MailThreadHelper
end
