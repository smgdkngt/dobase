// The theme switcher of the landing page. The page wears the app's own themes
// (themes.js, generated from the app), so picking one here shows what Dobase
// looks like in it: this page recolours, and the screenshot is the app in that theme.
(function () {
  var themes = window.DOBASE_THEMES || []
  var root = document.documentElement

  var store = {
    get: function (key) { try { return localStorage.getItem(key) || "" } catch (error) { return "" } },
    set: function (key, value) { try { value ? localStorage.setItem(key, value) : localStorage.removeItem(key) } catch (error) {} }
  }

  function find(name) {
    for (var i = 0; i < themes.length; i++) if (themes[i].name === name) return themes[i]
    return null
  }

  // Puts a theme's colours on the page, or with no theme takes them off again
  function wear(name) {
    var theme = find(name)
    if (themes[0]) Object.keys(themes[0].vars).forEach(function (property) { root.style.removeProperty(property) })
    root.style.removeProperty("color-scheme")
    delete root.dataset.theme
    delete root.dataset.themeMode
    if (!theme) return

    Object.keys(theme.vars).forEach(function (property) { root.style.setProperty(property, theme.vars[property]) })
    root.style.setProperty("color-scheme", theme.mode)
    root.dataset.theme = theme.name
    root.dataset.themeMode = theme.mode
  }

  function setTypeface(typeface) {
    if (typeface === "mono") root.dataset.typeface = "mono"
    else delete root.dataset.typeface
  }

  var current = find(store.get("dobase-theme")) ? store.get("dobase-theme") : ""
  var typeface = store.get("dobase-typeface") === "mono" ? "mono" : ""

  // Before the page is drawn, so it never flashes in other colours first
  wear(current)
  setTypeface(typeface)

  document.addEventListener("DOMContentLoaded", function () {
    var picker = document.querySelector("[data-theme-picker]")
    if (!picker || !themes.length) return

    var chips = picker.querySelector("[data-theme-chips]")
    var shot = document.querySelector("[data-theme-shot]")
    var darkShot = document.querySelector("[data-theme-shot-dark]")
    var caption = document.querySelector("[data-theme-name]")
    var order = [ "" ].concat(themes.map(function (theme) { return theme.name }))

    function chip(name, label, swatch) {
      var button = document.createElement("button")
      button.type = "button"
      button.className = "theme-chip"
      button.dataset.theme = name
      var dot = document.createElement("span")
      dot.className = "theme-chip-swatch"
      if (swatch) {
        dot.style.background = swatch.background
        dot.style.borderColor = swatch.border
        dot.style.setProperty("--dot", swatch.accent)
      }
      button.append(dot, document.createTextNode(label))
      button.addEventListener("click", function () { choose(name) })
      chips.append(button)
    }

    chip("", "Dobase", null)
    themes.forEach(function (theme) {
      chip(theme.name, theme.label, { background: theme.vars["--bg"], border: theme.vars["--border"], accent: theme.vars["--accent-solid"] })
    })

    // The app in the chosen theme and typeface. Without a theme it is the app's own
    // look, light or dark with the system, which the <picture> picks by itself.
    function show() {
      var suffix = (typeface ? "-mono" : "") + ".webp"
      var base = "screenshots/themes/"
      shot.src = base + (current || "dobase-light") + suffix
      darkShot.srcset = base + (current || "dobase-dark") + suffix
      var theme = find(current)
      shot.alt = "The Dobase workspace with four tools open, in " + (theme ? "the " + theme.label + " theme" : "its own look") + (typeface ? " and the monospace font" : "")
      if (caption) caption.textContent = theme ? theme.label : "Dobase"

      chips.querySelectorAll(".theme-chip").forEach(function (button) {
        var pressed = button.dataset.theme === current
        button.setAttribute("aria-pressed", String(pressed))
        // On a phone the themes are one row to swipe: keep the chosen one in sight
        if (pressed && chips.scrollWidth > chips.clientWidth) {
          chips.scrollTo({ left: button.offsetLeft - chips.offsetLeft - 16, behavior: "smooth" })
        }
      })
      picker.querySelectorAll("[data-typeface]").forEach(function (button) {
        button.setAttribute("aria-pressed", String(button.dataset.typeface === typeface))
      })
    }

    function change(update) {
      var still = window.matchMedia("(prefers-reduced-motion: reduce)").matches
      if (document.startViewTransition && !still) {
        var transition = document.startViewTransition(update)
        ;[ transition.ready, transition.finished, transition.updateCallbackDone ].forEach(function (settled) {
          if (settled) settled.catch(function () {})
        })
      } else {
        update()
      }
    }

    function choose(name) {
      change(function () {
        current = name
        store.set("dobase-theme", current)
        wear(current)
        show()
      })
    }

    picker.querySelectorAll("[data-typeface]").forEach(function (button) {
      button.addEventListener("click", function () {
        change(function () {
          typeface = button.dataset.typeface
          store.set("dobase-typeface", typeface)
          setTypeface(typeface)
          show()
        })
      })
    })

    // T tries the next theme, wherever you are on the page
    document.addEventListener("keydown", function (event) {
      if (event.key !== "t" && event.key !== "T") return
      if (event.metaKey || event.ctrlKey || event.altKey) return
      if (event.target.closest && event.target.closest("input, textarea, select, [contenteditable]")) return

      var step = event.shiftKey ? order.length - 1 : 1
      choose(order[(order.indexOf(current) + step) % order.length])
    })

    picker.hidden = false
    show()
  })
})()
