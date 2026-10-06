import { Controller } from "@hotwired/stimulus"
import { api } from "services/api"
import { showFlash } from "services/flash"
import { reportPresence } from "services/presence"
import { pageInUse } from "services/page_in_use"
import { floats, floating, drawnWith } from "services/float"
import { play } from "services/sound"
import { pageAddress, visitPage, tileOf } from "services/tile"

export default class extends Controller {
  static targets = ["itemModal", "itemDetailDialog", "addItemForm", "addItemInput", "addItemBtn", "completedSection", "completedToggle", "completedToggleLabel"]
  static values = { toolId: String }

  // ── Item detail modal ──

  connect() {
    if (this.hasItemDetailDialogTarget) {
      this._onModalClose = () => {
        reportPresence(null)
        // Floating over the workspace, the page goes with its dialog: the tile it came
        // from is the one that is drawn again
        if (floating) return
        // Closed because the page is going elsewhere: that visit stands
        if ("closedForNavigation" in this.itemDetailDialogTarget.dataset) {
          delete this.itemDetailDialogTarget.dataset.closedForNavigation
          return
        }
        // The dialog's "close" event doesn't fire until its CSS closing
        // transition finishes (allow-discrete keeps it in the top layer
        // until then), so this flag is consumed here rather than cleared
        // on a timer — a fixed delay would race the transition duration.
        if (this._suppressCloseVisit) {
          this._suppressCloseVisit = false
          return
        }
        // Opened again before this close was heard (the next todo clicked while the dialog
        // was fading out): the visit would close it. Its own close brings the refresh.
        if (this.itemDetailDialogTarget.open) return

        const url = pageAddress(this.element)
        url.searchParams.delete("item")
        this._refreshingAfterClose = true
        visitPage(this.element, url)
      }
      this.itemDetailDialogTarget.addEventListener("close", this._onModalClose)
      this._onBeforeRender = this._keepWhatWasStarted.bind(this)
      document.addEventListener("turbo:before-render", this._onBeforeRender)

      // Auto-open item if ?item=ID is in the URL
      const itemId = pageAddress(this.element).searchParams.get("item")
      if (itemId) this.#openItemById(itemId)
    }
  }

  disconnect() {
    if (this.hasItemDetailDialogTarget && this._onModalClose) {
      this.itemDetailDialogTarget.removeEventListener("close", this._onModalClose)
      document.removeEventListener("turbo:before-render", this._onBeforeRender)
    }
  }

  // The refresh after a close takes a moment to arrive. Whatever was started in the
  // meantime (the next todo opened, a title being typed) would be closed and emptied by
  // it, so then it is let go: the address is right already, and the page catches up at
  // the next close or save.
  _keepWhatWasStarted(event) {
    if (!this._refreshingAfterClose) return

    this._refreshingAfterClose = false
    if (pageInUse()) event.detail.render = () => {}
  }

  // The row body is a role="button" div (the row also holds a checkbox and a
  // drag handle), so Enter and Space have to open the item.
  // On a todo's row: Enter opens it, the space bar ticks it off (or on again)
  openItemKey(event) {
    if (event.key !== "Enter" && event.key !== " ") return
    event.preventDefault()
    if (event.key === "Enter") return this.openItem(event)

    event.currentTarget.closest("[data-sort-id]")?.querySelector("input[type='checkbox']")?.click()
  }

  openItem(event) {
    const itemId = event.currentTarget.dataset.itemId
    this.#openItemById(itemId)
  }

  #openItemById(itemId) {
    // In the workspace a todo's details float over all the tiles (services/float.js)
    if (floats(`/tools/${this.toolIdValue}/todo?item=${itemId}`, { clear: "item" })) return

    const url = `/tools/${this.toolIdValue}/todo/items/${itemId}`
    reportPresence(`todo:${itemId}`)

    // The page that floats over the workspace is drawn with the todo in its dialog
    // already: nothing to fetch, and no skeleton to look at
    if (this.hasItemModalTarget && drawnWith(this.itemModalTarget, itemId)) {
      this.itemDetailDialogTarget.showModal()
      this.itemModalTarget.querySelector("[autofocus], button, a[href]")?.focus()
      return
    }

    // Open immediately with a skeleton so the dialog's entrance isn't spent
    // staring at a blank sheet — content swaps in once the fetch resolves.
    if (this.hasItemModalTarget) {
      this.itemModalTarget.innerHTML = this._itemSkeletonHTML()
    }
    if (this.hasItemDetailDialogTarget) this.itemDetailDialogTarget.showModal()

    fetch(url, {
      headers: {
        "Accept": "text/html",
        "X-Requested-With": "XMLHttpRequest"
      }
    })
      .then(response => {
        // A missing item 404s server-side and redirects (eventually back to
        // this same list). Following that would inject a whole copy of the
        // page into the modal, whose own todo controller would repeat the
        // same auto-open and nest again. Bail out instead.
        if (!response.ok || response.redirected) {
          // Close without the "close" listener's own Turbo.visit — we're
          // already clearing the ?item= param below, and a second full-page
          // visit here would wipe out the flash we're about to show.
          if (this.hasItemDetailDialogTarget) {
            this._suppressCloseVisit = true
            this.itemDetailDialogTarget.close()
          }
          this._clearItemParam()
          showFlash("This item no longer exists.")
          return null
        }
        return response.text()
      })
      .then(html => {
        if (html === null) return
        if (this.hasItemModalTarget) {
          this.itemModalTarget.innerHTML = html
          // The dialog opened on a skeleton, so it kept the focus itself. Hand it
          // to the item, where the first Tab lands on its own buttons.
          this.itemModalTarget.querySelector("[autofocus], button, a[href]")?.focus()
        }
      })
      .catch(error => {
        console.error("Error loading item:", error)
      })
  }

  _itemSkeletonHTML() {
    return `
      <div class="flex flex-col w-full" style="max-height: 80vh; min-height: 60vh;">
        <div class="flex items-center gap-3 px-4 sm:px-5 py-3 sm:py-4 border-b border-border-light">
          <div class="skeleton w-5 h-5 rounded-full shrink-0"></div>
          <div class="flex-1 min-w-0">
            <div class="skeleton h-5 w-2/3"></div>
          </div>
        </div>
        <div class="detail-modal-body">
          <div class="detail-modal-main p-5 flex flex-col gap-3">
            <div class="skeleton h-4 w-full"></div>
            <div class="skeleton h-4 w-5/6"></div>
            <div class="skeleton h-4 w-1/2"></div>
          </div>
          <div class="detail-modal-aside p-4 flex flex-col gap-3">
            <div class="skeleton h-3 w-16"></div>
            <div class="skeleton h-8 w-full"></div>
            <div class="skeleton h-3 w-16"></div>
            <div class="skeleton h-8 w-full"></div>
          </div>
        </div>
      </div>
    `
  }

  _clearItemParam() {
    // (a tile in the workspace's page has no address in the window's)
    if (tileOf(this.element)) return

    const url = new URL(window.location.href)
    url.searchParams.delete("item")
    window.history.replaceState(history.state, "", url)
  }

  // ── Checkbox toggle ──

  async toggleCompletion(event) {
    const checkbox = event.currentTarget
    const url = checkbox.dataset.completeUrl
    const method = checkbox.checked ? "POST" : "DELETE"

    // The completion burst and its sound come before the network call
    if (checkbox.checked) {
      play("done")
      const wrapper = checkbox.closest("[data-checkbox-wrapper]")
      if (wrapper) {
        wrapper.classList.add("completing")
        wrapper.addEventListener("animationend", () => wrapper.classList.remove("completing"), { once: true })
      }
    }

    const result = await api(url, method)
    if (result) {
      visitPage(this.element)
    } else {
      checkbox.checked = !checkbox.checked
    }
  }

  // ── List rename ──

  startRenameList(event) {
    const span = event.currentTarget
    const listId = span.dataset.listId
    const currentName = span.textContent.trim()

    const input = document.createElement("input")
    input.type = "text"
    input.value = currentName
    input.className = "todo-list-name-input"

    const finishRename = async () => {
      const newName = input.value.trim()
      if (newName && newName !== currentName) {
        await api(`/tools/${this.toolIdValue}/todo/lists/${listId}`, "PATCH", { title: newName })
        span.textContent = newName
      }
      input.replaceWith(span)
    }

    input.addEventListener("blur", finishRename)
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter") { e.preventDefault(); input.blur() }
      if (e.key === "Escape") { input.value = currentName; input.blur() }
    })

    span.replaceWith(input)
    input.focus()
    input.select()
  }

  // ── Completed items toggle ──

  toggleCompleted(event) {
    const listId = event.currentTarget.dataset.listId
    const section = this.completedSectionTargets.find(s => s.dataset.listId === listId)
    const label = this.completedToggleLabelTargets.find(l => l.dataset.listId === listId)
    if (section) {
      const isHidden = !section.classList.contains("flex")
      section.classList.toggle("hidden", !isHidden)
      section.classList.toggle("flex", isHidden)
      if (label) {
        const count = label.textContent.match(/\d+/)?.[0] || ""
        label.textContent = isHidden ? `Hide ${count} completed` : `${count} completed`
      }
    }
  }

  // ── Add item form ──

  addItemToFirstList() {
    const firstBtn = this.addItemBtnTargets[0]
    if (firstBtn) firstBtn.click()
  }

  showAddItem(event) {
    const listId = event.currentTarget.dataset.listId
    const form = this.addItemFormTargets.find(f => f.dataset.listId === listId)
    const input = this.addItemInputTargets.find(i => i.dataset.listId === listId)
    if (form) {
      event.currentTarget.classList.add("hidden")
      form.classList.add("active")
      input?.focus()
    }
  }

  hideAddItem(event) {
    const listId = event.currentTarget.dataset.listId
    this._hideAddItemForm(listId)
  }

  addItemKeydown(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      event.target.form.requestSubmit()
    }
    if (event.key === "Escape") {
      this._hideAddItemForm(event.currentTarget.dataset.listId)
    }
  }

  // ── Private ──

  _hideAddItemForm(listId) {
    const form = this.addItemFormTargets.find(f => f.dataset.listId === listId)
    const input = this.addItemInputTargets.find(i => i.dataset.listId === listId)
    if (form) {
      form.classList.remove("active")
      if (input) input.value = ""
      const btn = this.addItemBtnTargets.find(b => b.dataset.listId === listId)
      if (btn) btn.classList.remove("hidden")
    }
  }
}
