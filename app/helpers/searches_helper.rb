# frozen_string_literal: true

module SearchesHelper
  SEARCH_ICONS = {
    card: "layout",
    todo: "check-square",
    document: "file-text",
    folder: "folder",
    file: "file",
    message: "message-circle",
    event: "calendar",
    mail: "mail"
  }.freeze

  # What a kind of result is called, one and many
  SEARCH_KIND_NAMES = {
    card: %w[card cards],
    todo: %w[todo todos],
    document: %w[document documents],
    folder: %w[folder folders],
    file: %w[file files],
    message: [ "chat message", "chat messages" ],
    event: %w[appointment appointments],
    mail: %w[mail mails]
  }.freeze

  def search_icon(kind)
    SEARCH_ICONS.fetch(kind, "search")
  end

  # "12 cards", or "50+ cards" past what is counted
  def search_kind_count(search, kind)
    count = search.totals.fetch(kind, 0)
    one, many = SEARCH_KIND_NAMES.fetch(kind, [ kind.to_s, kind.to_s.pluralize ])
    "#{count}#{'+' if search.beyond_most?(kind)} #{count == 1 ? one : many}"
  end

  # The text with every searched word in it marked. The text is someone's own, so it
  # is escaped, and only the <mark>s around it are markup.
  def search_marked(text, words)
    text = text.to_s
    return text if words.blank? || text.empty?

    pattern = Regexp.new("(#{words.sort_by { |word| -word.length }.map { |word| Regexp.escape(word) }.join('|')})", Regexp::IGNORECASE)
    safe_join(text.split(pattern).each_with_index.map { |part, index| index.odd? ? tag.mark(part) : part })
  end
end
