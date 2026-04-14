# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "sortablejs" # @1.15.7
pin "@github/hotkey", to: "@github--hotkey.js" # @3.1.4

pin_all_from "app/javascript/controllers", under: "controllers"
pin_all_from "app/javascript/services", under: "services"
pin_all_from "app/javascript/channels", under: "channels"

pin "@rails/actioncable", to: "actioncable.esm.js"

# Rhino Editor (TipTap-based rich text, replaces Trix)
pin "rhino-editor", to: "rhino-editor.js", preload: true
pin "@rails/activestorage", to: "activestorage.esm.js"
