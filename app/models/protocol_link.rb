# frozen_string_literal: true

# A web+dobase:// link: the scheme an installed app takes (the manifest's
# protocol_handlers, and the app `dobase app install` makes), naming a page of
# this instance. web+dobase://tools/12/mails is /tools/12/mails.
module ProtocolLink
  SCHEME = /\Aweb[+ ]dobase:/i # a browser that leaves the link unescaped turns + into a space

  # The link for a page of this instance
  def self.to(path)
    "web+dobase://#{path.to_s.sub(%r{\A/+}, "")}"
  end

  # The page a link names. Only ever a page on this instance: anything else is the
  # start page.
  def self.path(link)
    return "/" unless link.to_s.match?(SCHEME)

    path = link.sub(SCHEME, "").sub(%r{\A/+}, "")
    return "/" if path.include?("\\")

    uri = URI.parse("/#{path}")
    uri.host || uri.scheme ? "/" : uri.to_s
  rescue URI::InvalidURIError
    "/"
  end
end
