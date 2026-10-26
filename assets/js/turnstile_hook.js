// LiveView hook for the Cloudflare Turnstile widget (see MusicStudioWeb.FormGuard).
//
// Loads Cloudflare's script once, renders the widget explicitly (the element has
// phx-update="ignore", so LiveView leaves the widget's DOM alone), and resets it when the
// server pushes "turnstile:reset" (tokens are single-use). The widget adds a hidden
// cf-turnstile-response input that the enclosing form submits.
const SRC = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit"

let loading = null

const loadTurnstile = () => {
  if (window.turnstile) return Promise.resolve(window.turnstile)
  if (!loading) {
    loading = new Promise((resolve, reject) => {
      const script = document.createElement("script")
      script.src = SRC
      script.async = true
      script.onload = () => resolve(window.turnstile)
      script.onerror = reject
      document.head.appendChild(script)
    })
  }
  return loading
}

export default {
  mounted() {
    loadTurnstile().then(turnstile => {
      this.widgetId = turnstile.render(this.el, {sitekey: this.el.dataset.sitekey, size: "flexible"})
    })
    this.handleEvent("turnstile:reset", () => {
      if (window.turnstile && this.widgetId !== undefined) window.turnstile.reset(this.widgetId)
    })
  },
  destroyed() {
    if (window.turnstile && this.widgetId !== undefined) window.turnstile.remove(this.widgetId)
  },
}
