# frozen_string_literal: true

module FilesHelper
  # Rails' default list has no table or task-list tags, which markdown files do use.
  MARKDOWN_TAGS = (ActionView::Base.sanitized_allowed_tags.to_a +
    %w[table thead tbody tfoot tr td th input]).freeze
  MARKDOWN_ATTRIBUTES = (ActionView::Base.sanitized_allowed_attributes.to_a +
    %w[align colspan rowspan type checked disabled]).freeze

  # Markdown from an uploaded file, as HTML that is safe to put on the page: raw HTML in
  # the file is escaped rather than rendered, and the result goes through the sanitizer
  # too. Links open in a new tab, since a preview sits inside the app.
  def markdown_preview(text)
    html = Commonmarker.to_html(text.to_s, options: {
      render: { unsafe: false, hardbreaks: false },
      extension: { table: true, strikethrough: true, autolink: true, tasklist: true, footnotes: true }
    })

    safe = sanitize(html, tags: MARKDOWN_TAGS, attributes: MARKDOWN_ATTRIBUTES)
    safe.gsub("<a ", '<a target="_blank" rel="noopener noreferrer" ').html_safe
  end

  # The lexer for a file's name, or nil when Rouge doesn't know the language —
  # plain text, a log, a csv. Rouge guesses from the text as well, which lands
  # on something for anything, so only the name is trusted here.
  def code_lexer(filename)
    lexer = ::Rouge::Lexer.guess_by_filename(filename.to_s)
    lexer unless lexer == ::Rouge::Lexers::PlainText
  rescue ::Rouge::Guesser::Ambiguous => e
    e.alternatives.first
  rescue StandardError
    nil
  end

  # A code file with its keywords, strings and comments marked up. Rouge escapes
  # the text it formats, so what comes back is safe to put on the page.
  def highlighted_code(text, lexer)
    formatter = ::Rouge::Formatters::HTML.new
    formatter.format(lexer.new.lex(text.to_s)).html_safe
  end
end
