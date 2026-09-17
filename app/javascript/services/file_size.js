// The format HumanFileSize gives on the server: "0 B", "397 B", "8.5 KB", "25 MB"
const UNITS = ["B", "KB", "MB", "GB", "TB"]

export function formatFileSize(bytes) {
  let value = Math.max(0, Number(bytes) || 0)
  let unit = 0
  while (value >= 1024 && unit < UNITS.length - 1) {
    value /= 1024
    unit++
  }
  const rounded = unit === 0 ? Math.round(value) : Math.round(value * 10) / 10
  return `${rounded} ${UNITS[unit]}`
}
