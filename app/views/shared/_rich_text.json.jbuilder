# Renders a rich text attribute twice: as plain text under `name`, and as HTML
# under `name_html` (send HTML back when editing to keep formatting). The HTML is
# sanitized the same way Action Text sanitizes it for the browser, so API clients
# can display it as is.
json.set! name, rich_text.to_plain_text
json.set! "#{name}_html", rich_text.body ? sanitize_action_text_content(rich_text.body).to_str : ""
