const csrfToken = () => document.querySelector('meta[name="csrf-token"]')?.content

export async function api(path, method = "GET", body = null) {
  const opts = {
    method,
    headers: {
      "Accept": "application/json",
      "X-CSRF-Token": csrfToken()
    }
  }
  if (body) {
    opts.headers["Content-Type"] = "application/json"
    opts.body = JSON.stringify(body)
  }
  try {
    const res = await fetch(path, opts)
    if (!res.ok) {
      console.error(`API error: ${res.status} ${res.statusText}`)
      return null
    }
    const text = await res.text()
    return text ? JSON.parse(text) : { success: true }
  } catch (e) {
    console.error("API exception:", e)
    return null
  }
}

export function apiPatch(path, body) {
  return api(path, "PATCH", body)
}

export function apiPost(path, body) {
  return api(path, "POST", body)
}

export function apiDelete(path) {
  return api(path, "DELETE")
}
