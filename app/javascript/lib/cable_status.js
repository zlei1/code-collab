const disconnectedTokens = new Set()
let tokenSeed = 0

export function createCableToken(prefix = "cable") {
  tokenSeed += 1
  return `${prefix}-${tokenSeed}`
}

export function cableDisconnected(token) {
  if (!token) return
  const wasEmpty = disconnectedTokens.size === 0
  disconnectedTokens.add(token)
  if (wasEmpty) {
    window.dispatchEvent(new CustomEvent("cable:disconnected"))
  }
}

export function cableConnected(token) {
  if (!token) return
  const hadToken = disconnectedTokens.delete(token)
  if (hadToken && disconnectedTokens.size === 0) {
    window.dispatchEvent(new CustomEvent("cable:connected"))
  }
}
