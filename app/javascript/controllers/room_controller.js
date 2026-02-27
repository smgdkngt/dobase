import { Controller } from "@hotwired/stimulus"
import { api } from "services/api"

const LIVEKIT_URL = "https://cdn.jsdelivr.net/npm/livekit-client@2/dist/livekit-client.esm.mjs"

export default class extends Controller {
  static targets = [
    "preJoin",
    "inCall",
    "videoGrid",
    "localVideo",
    "participantCount",
    "micButton",
    "cameraButton",
    "screenButton",
    "participantTemplate"
  ]

  static values = {
    tokenUrl: String,
    userName: String
  }

  async join() {
    const { Room, RoomEvent, Track } = await import(LIVEKIT_URL)

    const tokenData = await api(this.tokenUrlValue, "POST")
    if (!tokenData?.token || !tokenData?.url) {
      console.error("Room: failed to fetch token", tokenData)
      return
    }

    this.LiveKitTrack = Track
    this.room = new Room({
      videoCaptureDefaults: { resolution: { width: 640, height: 360, frameRate: 24 } }
    })
    this.#bindRoomEvents(RoomEvent)

    await this.room.connect(tokenData.url, tokenData.token)
    await this.room.localParticipant.enableCameraAndMicrophone()

    this.#showInCall()
    this.#renderLocalParticipant()
    this.#renderExistingParticipants()
    this.updateParticipantCount()
  }

  leave() {
    this.room?.disconnect()
    this.room = null

    this.videoGridTarget.innerHTML = ""
    this.#clearLocalVideo()
    this.#showPreJoin()
    this.updateParticipantCount()
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
  }

  removeParticipant(identity) {
    const tile = this.videoGridTarget.querySelector(`[data-participant-id="${identity}"]`)
    tile?.remove()
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

  #bindRoomEvents(RoomEvent) {
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
          this.#updateMutedState(participant.identity, pub.kind, true)
        }
      })
      .on(RoomEvent.TrackUnmuted, (pub, participant) => {
        if (participant.identity !== this.room?.localParticipant?.identity) {
          this.#updateMutedState(participant.identity, pub.kind, false)
        }
      })
      .on(RoomEvent.Disconnected, () => {
        this.videoGridTarget.innerHTML = ""
        this.#clearLocalVideo()
        this.#showPreJoin()
        this.updateParticipantCount()
      })
  }

  #renderExistingParticipants() {
    this.room.remoteParticipants.forEach((participant) => {
      this.renderParticipant(participant)
      participant.trackPublications.forEach((pub) => {
        if (pub.isSubscribed && pub.track) {
          this.attachTrack(pub.track, participant.identity)
        }
      })
    })
  }

  #renderLocalParticipant() {
    const local = this.room.localParticipant
    const videoEl = this.localVideoTarget.querySelector("video")
    local.trackPublications.forEach((pub) => {
      if (pub.track?.kind === (this.LiveKitTrack?.Kind?.Video ?? "video")) {
        pub.track.attach(videoEl)
      }
    })
  }

  #clearLocalVideo() {
    const videoEl = this.localVideoTarget.querySelector("video")
    if (videoEl) videoEl.srcObject = null
  }

  #updateMutedState(identity, kind, muted) {
    const audioKind = this.LiveKitTrack?.Kind?.Audio ?? "audio"
    if (kind !== audioKind) return
    const tile = this.videoGridTarget.querySelector(`[data-participant-id="${identity}"]`)
    const mutedIcon = tile?.querySelector("[data-muted-icon]")
    mutedIcon?.classList.toggle("hidden", !muted)
  }

  #showInCall() {
    this.preJoinTarget.classList.add("hidden")
    this.inCallTarget.classList.remove("hidden")
  }

  #showPreJoin() {
    this.inCallTarget.classList.add("hidden")
    this.preJoinTarget.classList.remove("hidden")
  }
}
