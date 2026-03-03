import { Controller } from "@hotwired/stimulus"
import { api } from "services/api"

const LIVEKIT_URL = "https://cdn.jsdelivr.net/npm/livekit-client@2/dist/livekit-client.esm.mjs"

export default class extends Controller {
  static targets = [
    "preJoin",
    "inCall",
    "videoGrid",
    "emptyState",
    "localVideo",
    "participantCount",
    "micButton",
    "cameraButton",
    "screenButton",
    "participantTemplate",
    "audioSelect",
    "videoSelect",
    "previewVideo",
    "settingsAudioSelect",
    "settingsVideoSelect"
  ]

  static values = {
    tokenUrl: String,
    userName: String,
    toolPath: String,
    mode: { type: String, default: "" } // "", "full", or "pip"
  }

  connect() {
    // Reconnecting after page visit (turbo-permanent preserves parent, Stimulus reconnects)
    if (this.element._liveKitRoom) {
      this.room = this.element._liveKitRoom
      this.LiveKitTrack = this.element._liveKitTrack
      this._showInCall()
      this._renderLocalParticipant()
      this._renderExistingParticipants()
      this.updateParticipantCount()
      this._updateEmptyState()
      this._updateMode()
      this._applySidebarIndicator()
      this._listenForNavigation()
      return
    }

    // Server-rendered duplicate — an active call exists in #persistent-room
    const container = document.getElementById("persistent-room")
    const existingRoom = container?.querySelector("[data-controller~='room']")
    if (existingRoom && existingRoom !== this.element && existingRoom._liveKitRoom) {
      this._isDuplicate = true
      this.element.hidden = true
      // The existing controller's connect() handles mode switching
      return
    }

    // Normal first connect
    this.previewStream = null
    this._boundDeviceChange = () => this._enumerateDevices()
    navigator.mediaDevices?.addEventListener("devicechange", this._boundDeviceChange)
    this._enumerateDevices().then(() => this._requestDeviceAccess())
  }

  disconnect() {
    if (this._isDuplicate) return
    if (this.element._liveKitRoom) return // Being moved, skip cleanup

    this._stopNavigationListener()
    this._stopPreview()
    navigator.mediaDevices?.removeEventListener("devicechange", this._boundDeviceChange)
  }

  async join() {
    const { Room, RoomEvent, Track } = await import(LIVEKIT_URL)

    const tokenData = await api(this.tokenUrlValue, "POST")
    if (!tokenData?.token || !tokenData?.url) {
      console.error("Room: failed to fetch token", tokenData)
      return
    }

    this._stopPreview()

    const audioDeviceId = this.hasAudioSelectTarget ? this.audioSelectTarget.value : undefined
    const videoDeviceId = this.hasVideoSelectTarget ? this.videoSelectTarget.value : undefined

    this.LiveKitTrack = Track
    this.room = new Room({
      videoCaptureDefaults: {
        resolution: { width: 640, height: 360, frameRate: 24 }
      }
    })
    this._bindRoomEvents(RoomEvent)

    await this.room.connect(tokenData.url, tokenData.token)

    // Enable camera and mic with explicitly selected devices
    const camOptions = { resolution: { width: 640, height: 360, frameRate: 24 } }
    if (videoDeviceId) camOptions.deviceId = videoDeviceId
    const micOptions = {}
    if (audioDeviceId) micOptions.deviceId = audioDeviceId

    await this.room.localParticipant.setCameraEnabled(true, camOptions)
    await this.room.localParticipant.setMicrophoneEnabled(true, micOptions)

    // Sync settings selects with pre-join selections
    if (this.hasSettingsAudioSelectTarget) {
      this._syncSelect(this.settingsAudioSelectTarget, this.audioSelectTarget)
    }
    if (this.hasSettingsVideoSelectTarget) {
      this._syncSelect(this.settingsVideoSelectTarget, this.videoSelectTarget)
    }

    // Store LiveKit state on DOM element (survives Stimulus re-instantiation)
    this.element._liveKitRoom = this.room
    this.element._liveKitTrack = this.LiveKitTrack

    this._showInCall()
    this._renderLocalParticipant()
    this._renderExistingParticipants()
    this.updateParticipantCount()
    this._updateEmptyState()

    // Move into persistent container
    const container = document.getElementById("persistent-room")
    if (container && !container.contains(this.element)) {
      container.hidden = false
      container.appendChild(this.element)
      // appendChild triggers disconnect/connect → reconnect branch handles UI
    }
  }

  leave() {
    const wasOnRoomPage = window.location.pathname === this.toolPathValue

    this.room?.disconnect()
    this.room = null

    // Clear DOM-stored state
    delete this.element._liveKitRoom
    delete this.element._liveKitTrack

    // Clear mode, hide container, stop listening
    this.modeValue = ""
    this._stopNavigationListener()
    const container = document.getElementById("persistent-room")
    if (container) container.hidden = true
    this._removeSidebarIndicator()

    this.videoGridTarget.innerHTML = ""
    this._clearLocalVideo()
    this._showPreJoin()
    this.updateParticipantCount()

    // Reload room page to get fresh pre-join render
    // (element is stuck in hidden #persistent-room, server duplicate was hidden)
    if (wasOnRoomPage) {
      Turbo.visit(this.toolPathValue, { action: "replace" })
      return
    }

    this._requestDeviceAccess()
  }

  toggleMic() {
    if (!this.room) return
    const local = this.room.localParticipant
    const enabled = local.isMicrophoneEnabled
    local.setMicrophoneEnabled(!enabled)
    this.micButtonTarget.classList.toggle("text-error", enabled)
  }

  toggleCamera() {
    if (!this.room) return
    const local = this.room.localParticipant
    const enabled = local.isCameraEnabled
    local.setCameraEnabled(!enabled)
    this.cameraButtonTarget.classList.toggle("text-error", enabled)
  }

  async toggleScreen() {
    if (!this.room) return
    const local = this.room.localParticipant
    const isSharing = local.isScreenShareEnabled
    await local.setScreenShareEnabled(!isSharing)
    this.screenButtonTarget.classList.toggle("text-error", !isSharing)
  }

  async switchAudioDevice() {
    if (!this.room || !this.hasSettingsAudioSelectTarget) return
    const deviceId = this.settingsAudioSelectTarget.value
    if (deviceId) await this.room.switchActiveDevice("audioinput", deviceId)
  }

  async switchVideoDevice() {
    if (!this.room || !this.hasSettingsVideoSelectTarget) return
    const deviceId = this.settingsVideoSelectTarget.value
    if (deviceId) await this.room.switchActiveDevice("videoinput", deviceId)
  }

  startDrag(event) {
    if (this.modeValue !== "pip") return
    event.preventDefault()

    const rect = this.element.getBoundingClientRect()
    this._dragOffsetX = event.clientX - rect.left
    this._dragOffsetY = event.clientY - rect.top

    this._onPointerMove = (e) => {
      const x = Math.max(0, Math.min(e.clientX - this._dragOffsetX, window.innerWidth - this.element.offsetWidth))
      const y = Math.max(0, Math.min(e.clientY - this._dragOffsetY, window.innerHeight - this.element.offsetHeight))
      this.element.style.left = `${x}px`
      this.element.style.top = `${y}px`
      this.element.style.right = "auto"
      this.element.style.bottom = "auto"
    }
    this._onPointerUp = () => {
      document.removeEventListener("pointermove", this._onPointerMove)
      document.removeEventListener("pointerup", this._onPointerUp)
    }
    document.addEventListener("pointermove", this._onPointerMove)
    document.addEventListener("pointerup", this._onPointerUp)
  }

  async changePreviewCamera() {
    if (!this.previewStream || !this.hasVideoSelectTarget) return
    const deviceId = this.videoSelectTarget.value
    if (!deviceId) return

    this.previewStream.getVideoTracks().forEach(t => t.stop())

    try {
      const newStream = await navigator.mediaDevices.getUserMedia({
        video: { deviceId: { exact: deviceId } }
      })
      const newTrack = newStream.getVideoTracks()[0]
      this.previewStream.getVideoTracks().forEach(t => this.previewStream.removeTrack(t))
      this.previewStream.addTrack(newTrack)
      if (this.hasPreviewVideoTarget) {
        this.previewVideoTarget.srcObject = this.previewStream
      }
    } catch (e) {
      console.warn("Room: could not switch preview camera:", e)
    }
  }

  updateParticipantCount() {
    if (!this.hasParticipantCountTarget) return
    const count = this.room ? this.room.remoteParticipants.size + 1 : 0
    const label = count === 1 ? "1 participant" : `${count} participants`
    this.participantCountTarget.textContent = label
  }

  renderParticipant(participant) {
    const identity = participant.identity
    if (this.videoGridTarget.querySelector(`[data-participant-id="${identity}"]`)) return

    const clone = this.participantTemplateTarget.content.cloneNode(true)
    const tile = clone.firstElementChild
    tile.dataset.participantId = identity

    const nameEls = tile.querySelectorAll("[data-name]")
    nameEls.forEach(el => { el.textContent = participant.name || identity })

    const initialsEl = tile.querySelector("[data-initials]")
    if (initialsEl) initialsEl.textContent = this.initials(participant.name || identity)

    this.videoGridTarget.appendChild(clone)
    this._updateEmptyState()
  }

  removeParticipant(identity) {
    const tile = this.videoGridTarget.querySelector(`[data-participant-id="${identity}"]`)
    tile?.remove()
    this._updateEmptyState()
  }

  attachTrack(track, identity) {
    const tile = this.videoGridTarget.querySelector(`[data-participant-id="${identity}"]`)
    if (!tile) return

    if (track.kind === (this.LiveKitTrack?.Kind?.Video ?? "video")) {
      const videoEl = tile.querySelector("[data-video]")
      const placeholder = tile.querySelector("[data-placeholder]")
      if (videoEl) {
        track.attach(videoEl)
        videoEl.classList.remove("hidden")
      }
      if (placeholder) placeholder.classList.add("hidden")
    } else if (track.kind === (this.LiveKitTrack?.Kind?.Audio ?? "audio")) {
      const audioEl = track.attach()
      audioEl.autoplay = true
      tile.appendChild(audioEl)
    }
  }

  detachTrack(track, identity) {
    const tile = this.videoGridTarget.querySelector(`[data-participant-id="${identity}"]`)
    if (!tile) return

    if (track.kind === (this.LiveKitTrack?.Kind?.Video ?? "video")) {
      const videoEl = tile.querySelector("[data-video]")
      const placeholder = tile.querySelector("[data-placeholder]")
      if (videoEl) {
        track.detach(videoEl)
        videoEl.classList.add("hidden")
      }
      if (placeholder) placeholder.classList.remove("hidden")
    } else if (track.kind === (this.LiveKitTrack?.Kind?.Audio ?? "audio")) {
      track.detach()
    }
  }

  initials(name) {
    return (name || "")
      .trim()
      .split(/\s+/)
      .slice(0, 2)
      .map(w => w[0] || "")
      .join("")
      .toUpperCase()
  }

  // ── Private ──────────────────────────────────────────────────────────────

  _listenForNavigation() {
    if (this._onTurboRender) return
    this._onTurboRender = () => {
      if (!this.element._liveKitRoom) return
      this._updateMode()
      this._applySidebarIndicator()
    }
    document.addEventListener("turbo:render", this._onTurboRender)
  }

  _stopNavigationListener() {
    if (this._onTurboRender) {
      document.removeEventListener("turbo:render", this._onTurboRender)
      this._onTurboRender = null
    }
  }

  _updateMode() {
    const onRoomPage = window.location.pathname === this.toolPathValue
    this.modeValue = onRoomPage ? "full" : "pip"
    if (onRoomPage) {
      // Reset drag position
      this._resetPosition()
      // Hide server-rendered duplicate
      for (const el of document.querySelectorAll("[data-persistent-room-placeholder]")) {
        if (el !== this.element) el.hidden = true
      }
    }
  }

  _resetPosition() {
    this.element.style.left = ""
    this.element.style.top = ""
    this.element.style.right = ""
    this.element.style.bottom = ""
  }

  _applySidebarIndicator() {
    if (!this.toolPathValue) return
    const link = document.querySelector(`a.sidebar-tool-item[href="${this.toolPathValue}"]`)
    if (link) link.dataset.inCall = "true"
  }

  _removeSidebarIndicator() {
    document.querySelectorAll("[data-in-call]").forEach(el => delete el.dataset.inCall)
  }

  async _requestDeviceAccess() {
    try {
      this.previewStream = await navigator.mediaDevices.getUserMedia({ audio: true, video: true })
      if (this.hasPreviewVideoTarget) {
        this.previewVideoTarget.srcObject = this.previewStream
      }
    } catch (e) {
      console.warn("Room: could not access media devices:", e)
    }
    await this._enumerateDevices()
  }

  async _enumerateDevices() {
    try {
      const devices = await navigator.mediaDevices.enumerateDevices()
      const audioDevices = devices.filter(d => d.kind === "audioinput")
      const videoDevices = devices.filter(d => d.kind === "videoinput")

      if (this.hasAudioSelectTarget) this._populateSelect(this.audioSelectTarget, audioDevices, "Microphone")
      if (this.hasVideoSelectTarget) this._populateSelect(this.videoSelectTarget, videoDevices, "Camera")
      if (this.hasSettingsAudioSelectTarget) this._populateSelect(this.settingsAudioSelectTarget, audioDevices, "Microphone")
      if (this.hasSettingsVideoSelectTarget) this._populateSelect(this.settingsVideoSelectTarget, videoDevices, "Camera")
    } catch (e) {
      console.warn("Room: could not enumerate devices:", e)
    }
  }

  _populateSelect(selectEl, devices, fallbackLabel) {
    const currentValue = selectEl.value
    selectEl.innerHTML = ""
    devices.forEach((device, i) => {
      const option = document.createElement("option")
      option.value = device.deviceId
      option.textContent = device.label || `${fallbackLabel} ${i + 1}`
      selectEl.appendChild(option)
    })
    if (currentValue && [...selectEl.options].some(o => o.value === currentValue)) {
      selectEl.value = currentValue
    }
  }

  _syncSelect(target, source) {
    target.innerHTML = source.innerHTML
    target.value = source.value
  }

  _stopPreview() {
    if (this.previewStream) {
      this.previewStream.getTracks().forEach(t => t.stop())
      this.previewStream = null
    }
    if (this.hasPreviewVideoTarget) {
      this.previewVideoTarget.srcObject = null
    }
  }

  _bindRoomEvents(RoomEvent) {
    this.room
      .on(RoomEvent.ParticipantConnected, (participant) => {
        this.renderParticipant(participant)
        this.updateParticipantCount()
      })
      .on(RoomEvent.ParticipantDisconnected, (participant) => {
        this.removeParticipant(participant.identity)
        this.updateParticipantCount()
      })
      .on(RoomEvent.TrackSubscribed, (track, _pub, participant) => {
        this.attachTrack(track, participant.identity)
      })
      .on(RoomEvent.TrackUnsubscribed, (track, _pub, participant) => {
        this.detachTrack(track, participant.identity)
      })
      .on(RoomEvent.LocalTrackPublished, (pub) => {
        if (pub.track?.kind === (this.LiveKitTrack?.Kind?.Video ?? "video")) {
          pub.track.attach(this.localVideoTarget.querySelector("video"))
        }
      })
      .on(RoomEvent.LocalTrackUnpublished, (pub) => {
        if (pub.track?.kind === (this.LiveKitTrack?.Kind?.Video ?? "video")) {
          pub.track.detach(this.localVideoTarget.querySelector("video"))
        }
      })
      .on(RoomEvent.TrackMuted, (pub, participant) => {
        if (participant.identity !== this.room?.localParticipant?.identity) {
          this._updateMutedState(participant.identity, pub.kind, true)
        }
      })
      .on(RoomEvent.TrackUnmuted, (pub, participant) => {
        if (participant.identity !== this.room?.localParticipant?.identity) {
          this._updateMutedState(participant.identity, pub.kind, false)
        }
      })
      .on(RoomEvent.Disconnected, () => {
        this.videoGridTarget.innerHTML = ""
        this._clearLocalVideo()
        this._showPreJoin()
        this.updateParticipantCount()
      })
  }

  _renderExistingParticipants() {
    this.room.remoteParticipants.forEach((participant) => {
      this.renderParticipant(participant)
      participant.trackPublications.forEach((pub) => {
        if (pub.isSubscribed && pub.track) {
          this.attachTrack(pub.track, participant.identity)
        }
      })
    })
  }

  _renderLocalParticipant() {
    const local = this.room.localParticipant
    const videoEl = this.localVideoTarget.querySelector("video")
    local.trackPublications.forEach((pub) => {
      if (pub.track?.kind === (this.LiveKitTrack?.Kind?.Video ?? "video")) {
        pub.track.attach(videoEl)
      }
    })
  }

  _clearLocalVideo() {
    const videoEl = this.localVideoTarget.querySelector("video")
    if (videoEl) videoEl.srcObject = null
  }

  _updateMutedState(identity, kind, muted) {
    const audioKind = this.LiveKitTrack?.Kind?.Audio ?? "audio"
    if (kind !== audioKind) return
    const tile = this.videoGridTarget.querySelector(`[data-participant-id="${identity}"]`)
    const mutedIcon = tile?.querySelector("[data-muted-icon]")
    mutedIcon?.classList.toggle("hidden", !muted)
  }

  _updateEmptyState() {
    if (!this.hasEmptyStateTarget) return
    const hasRemote = this.videoGridTarget.querySelector("[data-participant-id]")
    this.emptyStateTarget.classList.toggle("hidden", !!hasRemote)
    this.videoGridTarget.classList.toggle("hidden", !hasRemote)
  }

  _showInCall() {
    this.preJoinTarget.classList.add("hidden")
    this.inCallTarget.classList.remove("hidden")
  }

  _showPreJoin() {
    this.inCallTarget.classList.add("hidden")
    this.preJoinTarget.classList.remove("hidden")
  }
}
