# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "sortablejs", to: "https://ga.jspm.io/npm:sortablejs@1.15.6/modular/sortable.esm.js"
pin "@github/hotkey", to: "https://ga.jspm.io/npm:@github/hotkey@3.1.1/dist/index.js"

pin_all_from "app/javascript/controllers", under: "controllers"
pin_all_from "app/javascript/services", under: "services"
pin_all_from "app/javascript/channels", under: "channels"

pin "@rails/actioncable", to: "actioncable.esm.js"

# Rhino Editor (TipTap-based rich text, replaces Trix)
pin "rhino-editor", to: "rhino-editor.js", preload: true
pin "@rails/activestorage", to: "activestorage.esm.js"
