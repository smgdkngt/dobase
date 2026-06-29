// Builds a TipTap suggestion config for @-mentions backed by a plain-DOM
// dropdown. No tippy/floating-ui dependency — the dropdown is a fixed-position
// element positioned at the caret rect reported by the suggestion plugin.
//
// users:         array of { id, name }
// onStateChange: called with true when the dropdown opens, false when it closes,
//                so the host controller can suppress enter-to-submit while open.
export function createMentionSuggestion({ users, onStateChange }) {
  return {
    char: "@",

    items: ({ query }) => {
      const q = query.toLowerCase()
      return users
        .filter((u) => u.name.toLowerCase().includes(q))
        .slice(0, 8)
    },

    render: () => {
      let dropdown
      let selectedIndex = 0
      let currentItems = []
      let currentCommand = null

      const setState = (active) => onStateChange?.(active)

      const renderItems = () => {
        dropdown.innerHTML = ""
        currentItems.forEach((item, index) => {
          const el = document.createElement("button")
          el.type = "button"
          el.className = "mention-suggestion-item"
          el.textContent = item.name
          if (index === selectedIndex) el.dataset.active = ""
          el.addEventListener("mousedown", (event) => {
            event.preventDefault()
            pick(index)
          })
          dropdown.appendChild(el)
        })
      }

      const position = (rect) => {
        if (!rect) return
        dropdown.style.left = `${rect.left}px`
        dropdown.style.top = `${rect.bottom + 4}px`
      }

      const pick = (index) => {
        const item = currentItems[index]
        if (item && currentCommand) {
          currentCommand({ id: String(item.id), label: item.name })
        }
      }

      return {
        onStart: (props) => {
          currentItems = props.items
          currentCommand = props.command
          selectedIndex = 0

          dropdown = document.createElement("div")
          dropdown.className = "mention-suggestion popover-menu"
          document.body.appendChild(dropdown)
          renderItems()
          position(props.clientRect?.())
          setState(true)
        },

        onUpdate: (props) => {
          currentItems = props.items
          currentCommand = props.command
          if (selectedIndex >= currentItems.length) selectedIndex = 0
          renderItems()
          position(props.clientRect?.())
        },

        onKeyDown: (props) => {
          const { event } = props
          if (event.key === "ArrowDown") {
            selectedIndex = (selectedIndex + 1) % currentItems.length
            renderItems()
            return true
          }
          if (event.key === "ArrowUp") {
            selectedIndex = (selectedIndex - 1 + currentItems.length) % currentItems.length
            renderItems()
            return true
          }
          if (event.key === "Enter" || event.key === "Tab") {
            if (currentItems.length === 0) return false
            pick(selectedIndex)
            return true
          }
          if (event.key === "Escape") {
            return true
          }
          return false
        },

        onExit: () => {
          dropdown?.remove()
          dropdown = null
          setState(false)
        }
      }
    }
  }
}
