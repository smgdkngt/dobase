# frozen_string_literal: true

module Mails
  # Who an address field offers while a name or an address is typed: the people this account
  # writes to, those written to lately and often first, then the people who wrote to it.
  # Mail sent from another mail program counts like mail sent from here: it is in Sent.
  class RecipientSuggestions
    Suggestion = Data.define(:address, :name, :score, :last_at)

    # A mail of the last month weighs four of a year ago
    RECENT = 30.days
    LATELY = 6.months
    CANDIDATES = 50

    def initialize(account)
      @account = account
    end

    def search(query, limit: 8)
      query = query.to_s.strip
      return [] if query.empty?

      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
      contacts = @account.contacts.where("name LIKE :q OR email_address LIKE :q", q: pattern)
        .order(times_contacted: :desc).limit(CANDIDATES).index_by(&:email_address)
      senders = @account.messages.where("from_address LIKE :q OR from_name LIKE :q", q: pattern)
        .where.not(from_address: [ nil, "" ]).group("LOWER(from_address)")
        .order(Arel.sql("MAX(sent_at) DESC")).limit(CANDIDATES).pluck(Arel.sql("LOWER(from_address)"))

      written = written_to("recipient.value LIKE ?", pattern)
      known_by_name = (contacts.keys + senders) - written.keys
      written.merge!(written_to("LOWER(recipient.value) IN (?)", known_by_name)) if known_by_name.any?

      addresses = (written.keys | contacts.keys | senders).select { |address| address.match?(/.@./) } - [ @account.email_address.downcase ]
      names = @account.names_for(addresses)

      addresses.map { |address| suggestion(address, names[address], written[address], contacts[address]) }
        .sort_by { |suggestion| [ starts_with?(suggestion, query) ? 0 : 1, -suggestion.score, -suggestion.last_at.to_i, suggestion.address ] }
        .first(limit)
    end

    private

    def suggestion(address, name, written, contact)
      score, last_at = written || [ 0, nil ]
      if contact && contact.times_contacted.positive?
        score = [ score, contact.times_contacted * weight(contact.last_contacted_at) ].max
        last_at = [ last_at, contact.last_contacted_at ].compact.max
      end
      Suggestion.new(address, name.presence, score, last_at)
    end

    # How much was sent to each address and when last, by address: [ score, time ]
    def written_to(condition, value)
      now = Time.current
      %w[to_addresses cc_addresses bcc_addresses].each_with_object({}) do |column, found|
        # (a list that isn't one, from long ago, would stop the whole query)
        list = "CASE WHEN json_valid(mail_messages.#{column}) THEN mail_messages.#{column} ELSE '[]' END"
        @account.messages.sent.joins("JOIN json_each(#{list}) AS recipient").where(condition, value)
          .group("LOWER(recipient.value)")
          .pluck(
            Arel.sql("LOWER(recipient.value)"),
            Arel.sql(ActiveRecord::Base.sanitize_sql_array([ "SUM(CASE WHEN mail_messages.sent_at >= ? THEN 4 WHEN mail_messages.sent_at >= ? THEN 2 ELSE 1 END)", now - RECENT, now - LATELY ])),
            Arel.sql("MAX(mail_messages.sent_at)")
          ).each do |address, score, last_at|
            last_at = last_at.is_a?(String) ? Time.find_zone("UTC").parse(last_at) : last_at
            before = found[address]
            found[address] = before ? [ before[0] + score, [ before[1], last_at ].compact.max ] : [ score, last_at ]
          end
      end
    end

    def weight(time)
      return 1 unless time

      if time >= RECENT.ago then 4
      elsif time >= LATELY.ago then 2
      else 1
      end
    end

    # What is typed begins a name, a part of a name, the address or its domain
    def starts_with?(suggestion, query)
      beginnings = suggestion.name.to_s.split(/[\s\-.,]+/) + [ suggestion.name.to_s, suggestion.address, suggestion.address.split("@").last ]
      beginnings.any? { |beginning| beginning.downcase.start_with?(query.downcase) }
    end
  end
end
