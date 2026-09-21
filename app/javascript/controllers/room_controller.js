import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "preJoin",
    "joinButton",
    "preJoinError",
    "preJoinErrorMessage",
    "inCall",
    "videoGrid",
    "emptyState",
    "contentArea",
    "spotlight",
    "spotlightVideo",
    "spotlightLabel",
    "reconnectingBanner",
    "localVideo",
    "localQualityDot",
    "localMutedIcon",
    "participantCount",
    "participantListBody",
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
    activityUrl: String,
    userName: String,
    toolPath: String,
    toolId: Number,
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
      // This room's own stale placeholder — the live instance (still in
      // #persistent-room) covers the page via CSS full-screen mode instead.
      if (existingRoom.dataset.roomToolIdValue === String(this.toolIdValue)) {
        this.element.hidden = true
      }
      // Otherwise this is a DIFFERENT room while a call is active elsewhere —
      // stay visible so CSS can show the "you're already in a call" state
      // (see body:has([data-room-mode-value="pip"]) in room.css). Hiding the
      // whole element here would blank this room's page instead.
      return
    }

    // Normal first connect
    this.previewStream = null
    this._boundDeviceChange = () => this._enumerateDevices()
    navigator.mediaDevices?.addEventListener("devicechange", this._boundDeviceChange)
    this._requestDeviceAccess()
  }

  disconnect() {
    this._tileObserver?.disconnect()
    this._tileObserver = null
    if (this._isDuplicate) return
    if (this.element._liveKitRoom) return // Being moved, skip cleanup

    this._stopNavigationListener()
    this._stopPreview()
    navigator.mediaDevices?.removeEventListener("devicechange", this._boundDeviceChange)
  }

  // Joining takes a moment (library, token, server) before anything changes on screen, so a
  // second click used to start a second join with the same identity. The server then drops
  // the first, and that join's failure took the second one down with it.
  async join() {
    if (this._joining || this.room) return
    this._joining = true
    this._setJoining(true)
    try {
      await this._join()
    } finally {
      this._joining = false
      this._setJoining(false)
    }
  }

  _setJoining(joining) {
    if (!this.hasJoinButtonTarget) return
    this.joinButtonTarget.disabled = joining
    this.joinButtonTarget.setAttribute("aria-busy", joining)
  }

  async _join() {
    this._clearJoinError()

    const { Room, RoomEvent, Track } = await import("livekit-client")
    this.LiveKitTrack = Track

    let tokenData
    try {
      tokenData = await this._fetchToken()
    } catch (e) {
      this._showJoinError(e.message, () => this.join())
      return
    }

    this._stopPreview()

    const audioDeviceId = this.hasAudioSelectTarget ? this.audioSelectTarget.value : undefined
    const videoDeviceId = this.hasVideoSelectTarget ? this.videoSelectTarget.value : undefined

    const room = new Room({
      videoCaptureDefaults: {
        resolution: { width: 640, height: 360, frameRate: 24 }
      }
    })
    this.room = room
    this._bindRoomEvents(RoomEvent)

    try {
      await room.connect(tokenData.url, tokenData.token)
    } catch (e) {
      console.error("Room: failed to connect", e)
      await this._teardownFailedRoom(room)
      this._showJoinError("Couldn't reach the video server. Check your connection and try again.", () => this.join())
      return
    }

    try {
      // Enable camera and mic with explicitly selected devices
      const camOptions = { resolution: { width: 640, height: 360, frameRate: 24 } }
      if (videoDeviceId) camOptions.deviceId = videoDeviceId
      const micOptions = {}
      if (audioDeviceId) micOptions.deviceId = audioDeviceId

      await room.localParticipant.setCameraEnabled(true, camOptions)
      await room.localParticipant.setMicrophoneEnabled(true, micOptions)
    } catch (e) {
      console.error("Room: failed to enable camera/microphone", e)
      await this._teardownFailedRoom(room)
      this._showJoinError(this._mediaErrorMessage(e), () => this.join())
      return
    }

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

    this._pingActivity(true)
    this._boundPageHide = () => this._pingActivity(false)
    window.addEventListener("pagehide", this._boundPageHide)

    // Move into persistent container
    const container = document.getElementById("persistent-room")
    if (container && !container.contains(this.element)) {
      container.hidden = false
      container.appendChild(this.element)
      // appendChild triggers disconnect/connect → reconnect branch handles UI
    }
  }

  async leave() {
    const wasOnRoomPage = window.location.pathname === this.toolPathValue

    this._pingActivity(false)
    if (this._boundPageHide) {
      window.removeEventListener("pagehide", this._boundPageHide)
      this._boundPageHide = null
    }

    // Stop all local media tracks (camera/mic/screen share) explicitly
    if (this.room) {
      this._leavingIntentionally = true
      this.room.localParticipant.trackPublications.forEach((pub) => {
        pub.track?.stop()
      })
      await this.room.disconnect()
    }
    this.room = null

    // Clear DOM-stored state
    delete this.element._liveKitRoom
    delete this.element._liveKitTrack

    // Clear UI state
    this.modeValue = ""
    this._stopNavigationListener()
    this._removeSidebarIndicator()
    this._resetSpotlight()
    this._hideReconnecting()

    // Remove element from persistent container (prevents stale re-init opening camera)
    const container = document.getElementById("persistent-room")
    if (container) container.hidden = true
    this.element.remove()

    // On room page: reload for fresh pre-join view
    if (wasOnRoomPage) {
      Turbo.visit(this.toolPathValue, { action: "replace" })
    }
  }

  retryAfterError() {
    this._clearJoinError()
    this._retryAction?.()
  }

  toggleMic() {
    if (!this.room) return
    const local = this.room.localParticipant
    const enabled = local.isMicrophoneEnabled
    local.setMicrophoneEnabled(!enabled)
    this.micButtonTarget.classList.toggle("text-error", enabled)
    this.micButtonTarget.title = enabled ? "Unmute microphone" : "Mute microphone"
    if (this.hasLocalMutedIconTarget) this.localMutedIconTarget.classList.toggle("hidden", !enabled)
  }

  toggleCamera() {
    if (!this.room) return
    const local = this.room.localParticipant
    const enabled = local.isCameraEnabled
    local.setCameraEnabled(!enabled)
    this.cameraButtonTarget.classList.toggle("text-error", enabled)
    this.cameraButtonTarget.title = enabled ? "Turn on camera" : "Turn off camera"
  }

  async toggleScreen() {
    if (!this.room) return
    try {
      await this.room.localParticipant.setScreenShareEnabled(!this.room.localParticipant.isScreenShareEnabled)
      // Button state and title follow LocalTrackPublished/Unpublished so it stays
      // correct even when the share is stopped from the browser's own UI.
    } catch (e) {
      console.warn("Room: could not toggle screen share:", e)
    }
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
    if (this.hasParticipantCountTarget) {
      const count = this.room ? this.room.remoteParticipants.size + 1 : 0
      this.participantCountTarget.textContent = count === 1 ? "1 participant" : `${count} participants`
    }
    this._renderParticipantList()
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
      // Reuse the existing audio element on reconnect (turbo navigation re-runs
      // attachTrack via _renderExistingParticipants). track.attach() with no
      // argument creates a fresh element every call, so without this guard each
      // tool switch would stack another <audio> playing the same stream.
      const existing = tile.querySelector(`audio[data-audio-sid="${track.sid}"]`)
      if (existing) {
        track.attach(existing)
      } else {
        const audioEl = track.attach()
        audioEl.dataset.audioSid = track.sid
        audioEl.autoplay = true
        tile.appendChild(audioEl)
      }
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
      track.detach().forEach((el) => el.remove())
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

  async _fetchToken() {
    let res
    try {
      res = await fetch(this.tokenUrlValue, {
        method: "POST",
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
        }
      })
    } catch (_e) {
      throw new Error("Couldn't reach the server. Check your connection and try again.")
    }

    let data = null
    try {
      data = await res.json()
    } catch (_e) {
      // No/invalid JSON body — fall through to the generic error below
    }

    if (!res.ok || !data?.token || !data?.url) {
      throw new Error(data?.error || "This room isn't available right now. Try again in a moment.")
    }
    return data
  }

  _mediaErrorMessage(e) {
    switch (e?.name) {
      case "NotAllowedError":
        return "Camera and microphone access is blocked. Allow access in your browser's settings, then try again."
      case "NotFoundError":
        return "No camera or microphone was found. Connect a device and try again."
      case "NotReadableError":
        return "Your camera or microphone is already in use by another application."
      default:
        return "Couldn't access your camera or microphone. Try again."
    }
  }

  // Takes down the room a failed join made, and only resets the page if it's still the current one
  async _teardownFailedRoom(room) {
    if (!room) return
    const current = room === this.room
    // Suppress the Disconnected handler's own recovery (pre-join rebuild +
    // error banner) — join() is already handling this failure and will show
    // its own, more specific message right after this resolves.
    if (current) this._leavingIntentionally = true
    try {
      await room.disconnect()
    } catch (_e) {
      // Already gone
    }
    if (!current) return
    this.room = null
    await this._requestDeviceAccess()
  }

  _showJoinError(message, retry) {
    this._retryAction = retry
    if (this.hasPreJoinErrorMessageTarget) this.preJoinErrorMessageTarget.textContent = message
    if (this.hasPreJoinErrorTarget) this.preJoinErrorTarget.classList.remove("hidden")
  }

  _clearJoinError() {
    if (this.hasPreJoinErrorTarget) this.preJoinErrorTarget.classList.add("hidden")
  }

  _pingActivity(active) {
    if (!this.activityUrlValue) return
    // A leave ping carries how many participants are still in the call, so the
    // sidebar dot only clears for everyone once the last one has left.
    const url = active
      ? this.activityUrlValue
      : `${this.activityUrlValue}?remaining=${this._remainingParticipantCount()}`
    fetch(url, {
      method: active ? "POST" : "DELETE",
      keepalive: true,
      headers: { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content }
    }).catch(() => {})
  }

  // Everyone but us: the ping is sent while we are still connected.
  _remainingParticipantCount() {
    return this.room?.remoteParticipants?.size ?? 0
  }

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
    if (!this.toolIdValue) return
    const link = document.querySelector(`[data-tool-id="${this.toolIdValue}"]`)
    if (link) link.dataset.inCall = "true"
  }

  _removeSidebarIndicator() {
    if (!this.toolIdValue) return
    const link = document.querySelector(`[data-tool-id="${this.toolIdValue}"]`)
    if (link) delete link.dataset.inCall
  }

  async _requestDeviceAccess() {
    try {
      this.previewStream = await navigator.mediaDevices.getUserMedia({ audio: true, video: true })
      if (this.hasPreviewVideoTarget) {
        this.previewVideoTarget.srcObject = this.previewStream
      }
      this._clearJoinError()
    } catch (e) {
      console.warn("Room: could not access media devices:", e)
      this._showJoinError(this._mediaErrorMessage(e), () => this._requestDeviceAccess())
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
        this._hideSpotlight(participant.identity)
        this.removeParticipant(participant.identity)
        this.updateParticipantCount()
      })
      .on(RoomEvent.TrackSubscribed, (track, pub, participant) => {
        if (track.source === this.LiveKitTrack?.Source?.ScreenShare) {
          this._showSpotlight(track, participant)
          return
        }
        this.attachTrack(track, participant.identity)
        if (track.kind === (this.LiveKitTrack?.Kind?.Audio ?? "audio") && pub.isMuted) {
          this._updateMutedState(participant.identity, track.kind, true)
        }
      })
      .on(RoomEvent.TrackUnsubscribed, (track, _pub, participant) => {
        if (track.source === this.LiveKitTrack?.Source?.ScreenShare) {
          this._hideSpotlight(participant.identity)
          return
        }
        this.detachTrack(track, participant.identity)
      })
      .on(RoomEvent.LocalTrackPublished, (pub) => {
        const track = pub.track
        const source = this.LiveKitTrack?.Source
        if (!track || !source) return
        if (track.source === source.Camera) {
          track.attach(this.localVideoTarget.querySelector("video"))
        } else if (track.source === source.ScreenShare) {
          this._showSpotlight(track, this.room.localParticipant)
          if (this.hasScreenButtonTarget) {
            this.screenButtonTarget.classList.add("text-error")
            this.screenButtonTarget.title = "Stop sharing"
          }
        }
      })
      .on(RoomEvent.LocalTrackUnpublished, (pub) => {
        const track = pub.track
        const source = this.LiveKitTrack?.Source
        if (!track || !source) return
        if (track.source === source.Camera) {
          track.detach(this.localVideoTarget.querySelector("video"))
        } else if (track.source === source.ScreenShare) {
          this._hideSpotlight(this.room.localParticipant.identity)
          if (this.hasScreenButtonTarget) {
            this.screenButtonTarget.classList.remove("text-error")
            this.screenButtonTarget.title = "Share screen"
          }
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
      .on(RoomEvent.ActiveSpeakersChanged, (speakers) => this._updateActiveSpeakers(speakers))
      .on(RoomEvent.ConnectionQualityChanged, (quality, participant) => this._updateConnectionQuality(quality, participant))
      .on(RoomEvent.Reconnecting, () => this._showReconnecting())
      .on(RoomEvent.Reconnected, () => this._hideReconnecting())
      .on(RoomEvent.Disconnected, () => {
        this.room = null
        this._resetSpotlight()
        this._hideReconnecting()
        this.videoGridTarget.innerHTML = ""
        this._clearLocalVideo()
        this.updateParticipantCount()
        if (!this._leavingIntentionally) {
          this._showPreJoin()
          this._requestDeviceAccess()
          this._showJoinError("You were disconnected from the call. Check your connection and try again.", () => this.join())
        }
        this._leavingIntentionally = false
      })
  }

  _renderExistingParticipants() {
    this.room.remoteParticipants.forEach((participant) => {
      this.renderParticipant(participant)
      participant.trackPublications.forEach((pub) => {
        if (!pub.isSubscribed || !pub.track) return
        if (pub.track.source === this.LiveKitTrack?.Source?.ScreenShare) {
          this._showSpotlight(pub.track, participant)
          return
        }
        this.attachTrack(pub.track, participant.identity)
        if (pub.kind === (this.LiveKitTrack?.Kind?.Audio ?? "audio") && pub.isMuted) {
          this._updateMutedState(participant.identity, pub.kind, true)
        }
      })
    })
  }

  _renderLocalParticipant() {
    const local = this.room.localParticipant
    const videoEl = this.localVideoTarget.querySelector("video")
    const source = this.LiveKitTrack?.Source
    local.trackPublications.forEach((pub) => {
      if (!pub.track || !source) return
      if (pub.track.source === source.Camera) {
        pub.track.attach(videoEl)
      } else if (pub.track.source === source.ScreenShare) {
        this._showSpotlight(pub.track, local)
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

  _showSpotlight(track, participant) {
    if (!this.hasSpotlightTarget || !this.room) return
    this._spotlightIdentity = participant.identity
    const isLocal = participant.identity === this.room.localParticipant.identity
    if (this.hasSpotlightLabelTarget) {
      this.spotlightLabelTarget.textContent = isLocal
        ? "You're presenting"
        : `${participant.name || participant.identity} is presenting`
    }
    if (this.hasSpotlightVideoTarget) track.attach(this.spotlightVideoTarget)
    this.spotlightTarget.classList.remove("hidden")
    if (this.hasContentAreaTarget) this.contentAreaTarget.dataset.hasSpotlight = "true"
    this._updateEmptyState()
  }

  _hideSpotlight(identity) {
    if (!this.hasSpotlightTarget || this._spotlightIdentity !== identity) return
    this._resetSpotlight()
  }

  _resetSpotlight() {
    if (this.hasSpotlightVideoTarget) this.spotlightVideoTarget.srcObject = null
    if (this.hasSpotlightTarget) this.spotlightTarget.classList.add("hidden")
    if (this.hasContentAreaTarget) delete this.contentAreaTarget.dataset.hasSpotlight
    this._spotlightIdentity = null
    this._updateEmptyState()
  }

  _showReconnecting() {
    if (this.hasReconnectingBannerTarget) this.reconnectingBannerTarget.classList.remove("hidden")
  }

  _hideReconnecting() {
    if (this.hasReconnectingBannerTarget) this.reconnectingBannerTarget.classList.add("hidden")
  }

  _updateConnectionQuality(quality, participant) {
    if (!this.room) return
    const poor = quality === "poor" || quality === "lost"
    const isLocal = participant.identity === this.room.localParticipant.identity
    const dot = isLocal
      ? (this.hasLocalQualityDotTarget ? this.localQualityDotTarget : null)
      : this.videoGridTarget.querySelector(`[data-participant-id="${participant.identity}"] [data-quality-dot]`)
    if (!dot) return
    dot.classList.toggle("hidden", !poor)
    dot.title = quality === "lost" ? "Connection lost" : "Poor connection"
  }

  _updateActiveSpeakers(speakers) {
    const speakingIds = new Set(speakers.map(p => p.identity))
    const localId = this.room?.localParticipant?.identity
    this.videoGridTarget.querySelectorAll("[data-participant-id]").forEach((tile) => {
      tile.classList.toggle("room-speaking", speakingIds.has(tile.dataset.participantId))
    })
    if (this.hasLocalVideoTarget) {
      this.localVideoTarget.classList.toggle("room-speaking", localId != null && speakingIds.has(localId))
    }
  }

  _renderParticipantList() {
    if (!this.hasParticipantListBodyTarget) return
    this.participantListBodyTarget.innerHTML = ""
    if (this.room) {
      this._appendParticipantRow(this.userNameValue || "You", this.initials(this.userNameValue), true)
    }
    this.videoGridTarget.querySelectorAll("[data-participant-id]").forEach((tile) => {
      const name = tile.querySelector("[data-name]")?.textContent || "Participant"
      const initialsText = tile.querySelector("[data-initials]")?.textContent || this.initials(name)
      this._appendParticipantRow(name, initialsText, false)
    })
  }

  _appendParticipantRow(name, initialsText, isLocal) {
    const row = document.createElement("div")
    row.className = "room-participant-row"

    const avatar = document.createElement("div")
    avatar.className = "room-participant-row-avatar"
    avatar.textContent = initialsText
    row.appendChild(avatar)

    const nameEl = document.createElement("span")
    nameEl.className = "room-participant-row-name"
    nameEl.textContent = isLocal ? `${name} (you)` : name
    row.appendChild(nameEl)

    this.participantListBodyTarget.appendChild(row)
  }

  _updateEmptyState() {
    if (!this.hasEmptyStateTarget) return
    const hasRemote = this.videoGridTarget.querySelector("[data-participant-id]")
    const hasSpotlight = this._spotlightIdentity != null
    this.emptyStateTarget.classList.toggle("hidden", !!hasRemote || hasSpotlight)
    this.videoGridTarget.classList.toggle("hidden", !hasRemote)
    this._layoutTiles()
  }

  // Every tile is 16:9 and as large as the grid allows for however many there
  // are, instead of one stretched across a wide screen and cropped to a nose.
  // Tries each number of columns and keeps the one with the biggest tiles.
  _layoutTiles() {
    const grid = this.videoGridTarget
    this._tileObserver ||= new ResizeObserver(() => this._layoutTiles())
    this._tileObserver.observe(grid)

    const count = grid.querySelectorAll("[data-participant-id]").length
    if (count === 0 || grid.clientWidth === 0) return

    const style = getComputedStyle(grid)
    const gap = parseFloat(style.columnGap) || 0
    const width = grid.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight)
    const height = grid.clientHeight - parseFloat(style.paddingTop) - parseFloat(style.paddingBottom)

    let best = 0
    for (let columns = 1; columns <= count; columns++) {
      const rows = Math.ceil(count / columns)
      const tileWidth = Math.min(
        (width - gap * (columns - 1)) / columns,
        ((height - gap * (rows - 1)) / rows) * 16 / 9
      )
      best = Math.max(best, tileWidth)
    }

    grid.style.setProperty("--room-tile-width", `${Math.floor(best)}px`)
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
