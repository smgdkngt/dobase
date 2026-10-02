// A default avatar (two letters, no picture) drawn in the browser gets the look the
// server gives the same person everywhere else: User#avatar_look, components.css
export function wearLook(face, look) {
  if (!look) return

  face.dataset.avatarHue = look.hue
  face.dataset.avatarSecond = look.second
  face.dataset.avatarPattern = look.pattern
}
