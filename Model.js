// Pure parsing and formatting helpers for the lee.syncthing widget.
// Kept free of QML imports so logic stays testable and cheap.

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: false, installed: false, running: false, lastError: "No output from syncthing helper" }
  try {
    var parsed = JSON.parse(text)
    if (parsed && parsed.ok === true) return parsed
    return {
      ok: false,
      installed: parsed ? parsed.installed === true : false,
      running: parsed ? parsed.running === true : false,
      lastError: String((parsed && parsed.lastError) || "Syncthing status failed")
    }
  } catch (error) {
    return { ok: false, installed: false, running: false, lastError: "Invalid syncthing helper output: " + String(error) }
  }
}

function bytesText(value) {
  var n = Number(value || 0)
  if (!isFinite(n) || n <= 0) return "0 B"
  var units = ["B", "KB", "MB", "GB", "TB"]
  var i = 0
  while (n >= 1000 && i < units.length - 1) {
    n /= 1000
    i++
  }
  return (i === 0 ? n.toFixed(0) : n.toFixed(1)) + " " + units[i]
}

function uptimeText(seconds) {
  var total = Math.max(0, Math.floor(Number(seconds || 0)))
  var days = Math.floor(total / 86400)
  var hours = Math.floor((total % 86400) / 3600)
  var minutes = Math.floor((total % 3600) / 60)
  if (days > 0) return days + " d " + hours + " h"
  if (hours > 0) return hours + " h " + minutes + " m"
  return minutes + " m"
}

function percentText(value) {
  var n = Number(value)
  if (!isFinite(n)) return ""
  return Math.round(n) + "%"
}

function folderStateText(folder) {
  if (!folder) return "Unknown"
  if (folder.paused) return "Paused"
  var state = String(folder.state || "unknown")
  switch (state) {
    case "idle": return "Up to date"
    case "scanning": return "Scanning"
    case "syncing": return "Syncing"
    case "sync-preparing": return "Preparing to sync"
    case "wait-for-scan": return "Waiting to scan"
    case "error": return "Error"
    case "unknown": return "Unknown"
    default: return state.charAt(0).toUpperCase() + state.slice(1)
  }
}

function folderStateGlyph(folder) {
  if (!folder) return ""
  if (folder.paused) return "󰏤"
  switch (String(folder.state || "")) {
    case "syncing": return "󰁦"
    case "sync-preparing": return "󰁦"
    case "scanning": return "󰑐"
    case "error": return "󰀍"
    default: return ""
  }
}

function folderMetaText(folder) {
  if (!folder) return ""
  var parts = [folderStateText(folder)]
  if (folder.paused) return parts[0]
  if (folder.state === "syncing") {
    parts.push(bytesText(folder.globalBytes - folder.needBytes) + " of " + bytesText(folder.globalBytes))
  } else if (folder.state === "idle" && folder.globalBytes > 0) {
    parts.push(bytesText(folder.globalBytes))
  }
  if (folder.errors > 0) parts.push(folder.errors + (folder.errors === 1 ? " issue" : " issues"))
  if (folder.invalid) parts.push("needs attention")
  return parts.join(" · ")
}

function folderHasProblem(folder) {
  if (!folder) return false
  return folder.errors > 0 || folder.state === "error" || !!folder.invalid
}

function deviceMetaText(device) {
  if (!device) return ""
  if (device.paused) return "Paused"
  if (!device.connected) return "Disconnected"
  var parts = []
  var percent = percentText(device.completion)
  if (percent !== "" && Number(device.completion) < 100) parts.push(percent + " complete")
  if (device.address) parts.push(String(device.address))
  var link = linkTypeLabel(device.linkType)
  if (link !== "") parts.push(link)
  if (device.clientVersion) parts.push(device.clientVersion)
  return parts.length > 0 ? parts.join(" · ") : "Connected"
}

function linkTypeLabel(linkType) {
  var value = String(linkType || "")
  if (value.indexOf("relay") === 0) return "relay"
  if (value.indexOf("quic") === 0) return "quic"
  if (value.indexOf("tcp") === 0) return "tcp"
  return ""
}

function deviceGlyph(device) {
  if (!device) return ""
  if (device.paused) return "󰏤"
  if (device.connected) return "󰛳"
  return "󰛲"
}
