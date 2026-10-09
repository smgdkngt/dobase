# frozen_string_literal: true

module FilesHelper
  # Rails' default list has no table or task-list tags, which markdown files do use.
  MARKDOWN_TAGS = (ActionView::Base.sanitized_allowed_tags.to_a +
    %w[table thead tbody tfoot tr td th input]).freeze
  MARKDOWN_ATTRIBUTES = (ActionView::Base.sanitized_allowed_attributes.to_a +
    %w[align colspan rowspan type checked disabled]).freeze

  # Markdown from a file someone sent, as HTML that is safe to put on the page: raw HTML in
  # the file is escaped rather than rendered, and the result goes through the sanitizer
  # too. Links open in a new tab, since a preview sits inside the app.
  def markdown_preview(text)
    html = Commonmarker.to_html(text.to_s, options: {
      render: { unsafe: false, hardbreaks: false },
      extension: { table: true, strikethrough: true, autolink: true, tasklist: true, footnotes: true }
    })

    safe = sanitize(html, tags: MARKDOWN_TAGS, attributes: MARKDOWN_ATTRIBUTES)
    externalize_links(pictures_as_links(safe), rel: "noopener noreferrer")
  end

  # A picture in a markdown file is at an address outside the app, and loading it tells
  # whoever sent the file that it was opened, when and from where: what mail keeps
  # pictures from outside back for. So a preview loads none; a picture is a link to it.
  def pictures_as_links(html)
    fragment = Nokogiri::HTML5.fragment(html.to_s)
    fragment.css("img").each do |picture|
      address = picture["src"].to_s
      text = picture["alt"].presence || address
      if address.match?(%r{\Ahttps?://}i)
        link = fragment.document.create_element("a", href: address)
        link.content = text
        picture.replace(link)
      else
        picture.replace(fragment.document.create_text_node(text))
      end
    end
    fragment.to_html
  end

  # Where a file is shown in the app (Tools::FilePreviewsController): `file` is what a
  # record has attached, `attachment.file` or one of a message's `files`
  def file_preview_path(tool, file, **options)
    tool_file_preview_path(tool, file.respond_to?(:attachment) ? file.attachment : file, **options)
  end

  def file_preview_url(tool, file, **options)
    tool_file_preview_url(tool, file.respond_to?(:attachment) ? file.attachment : file, **options)
  end

  # A link that opens a file in the viewer over the page (shared/file_viewer) instead of
  # going anywhere
  def link_to_file_preview(tool, file, **options, &block)
    options[:data] = (options[:data] || {}).merge(turbo_frame: "file_viewer")
    link_to(file_preview_path(tool, file), **options, &block)
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
