function emptyStatus() {
  return {
    ok: true,
    helper: { state: "unknown", socket: "", installed: "", plugin: "", service: false },
    capture_dir: "",
    radio_count: 0,
    monitor_count: 0,
    capture_count: 0,
    station_count: 0,
    radios: [],
    air: [],
    clients: [],
    captures: [],
    warning: ""
  }
}

function parseStatus(raw) {
  var text = String(raw || "").replace(/^\uFEFF/, "").trim()
  if (!text) return emptyStatus()
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return emptyStatus()
    if (!parsed.helper) parsed.helper = emptyStatus().helper
    if (!Array.isArray(parsed.radios)) parsed.radios = []
    if (!Array.isArray(parsed.air)) parsed.air = []
    if (!Array.isArray(parsed.clients)) parsed.clients = []
    if (!Array.isArray(parsed.captures)) parsed.captures = []
    return parsed
  } catch (error) {
    var fallback = emptyStatus()
    fallback.ok = false
    fallback.error = "status parse error"
    return fallback
  }
}

function helperState(status) {
  var helper = (status && status.helper) || {}
  return helper.state || "unknown"
}

function helperReady(status) {
  return helperState(status) === "running"
}

function formatBytes(bytes) {
  var n = Number(bytes)
  if (!isFinite(n) || n < 0) n = 0
  if (n < 1024) return Math.round(n) + " B"
  if (n < 1024 * 1024) return (n / 1024).toFixed(1) + " KB"
  if (n < 1024 * 1024 * 1024) return (n / (1024 * 1024)).toFixed(1) + " MB"
  return (n / (1024 * 1024 * 1024)).toFixed(2) + " GB"
}

function formatRssi(rssi) {
  if (rssi === undefined || rssi === null || rssi === "") return "—"
  var n = Number(rssi)
  if (!isFinite(n)) return "—"
  return Math.round(n) + " dBm"
}

function formatWidth(mhz) {
  var n = Number(mhz)
  if (!isFinite(n) || n <= 0) return "—"
  return Math.round(n) + " MHz"
}

function bandLabel(band) {
  if (!band) return ""
  return String(band) + " GHz"
}

function isDisabled(radio) {
  return !!(radio && radio.disabled)
}

function roleLabel(role) {
  if (role === "monitor") return "Monitor"
  if (role === "hopper") return "Scan"
  if (role === "active") return "Scan"
  if (role === "disabled") return "Disabled"
  return "Station"
}

function radioRoleLabel(radio) {
  if (!radio) return "Station"
  if (isDisabled(radio)) return "Disabled"
  if (radio.role === "active" && radio.hop_channels && radio.hop_channels.length)
    return "Scan"
  return roleLabel(radio.role)
}

function busLabel(bus) {
  if (bus === "usb") return "USB"
  if (bus === "pci") return "PCIe"
  if (bus === "sdio") return "SDIO"
  return bus || "radio"
}

function radioTitle(radio) {
  if (!radio) return "Radio"
  return radio.product || radio.driver || radio.phy || "Radio"
}

function radioCaps(radio) {
  return (radio && radio.capabilities) || {}
}

function capChannels(radio, band) {
  var map = radioCaps(radio).channels || {}
  var list = map[band]
  if (list && list.length) {
    var copy = []
    for (var i = 0; i < list.length; i++) copy.push(Number(list[i]))
    return copy
  }
  if (band === "2.4") return radio24(radio)
  if (band === "5") return radio5(radio)
  if (band === "6") return radio6(radio)
  return []
}

function capMaxWidth(radio, band) {
  var b = String(band || (radio && radio.band) || "")
  var caps = radioCaps(radio)
  var advertised = 0
  var learned = 0
  if (caps.max_width && caps.max_width[b] != null) advertised = Number(caps.max_width[b]) || 0
  if (caps.learned_width && caps.learned_width[b] != null) learned = Number(caps.learned_width[b]) || 0
  var w = Math.max(advertised, learned)
  var driver = String((radio && radio.driver) || "")
  // MT7921U is 80 MHz silicon. The helper used to invent 160 MHz; don't offer it.
  if (driver.indexOf("mt7921") === 0) {
    if (b === "2.4") return Math.min(w || 40, 40)
    return Math.min(w || 80, 80)
  }
  if (b === "2.4") return Math.min(w || 40, 40)
  if (w > 0) return w
  if (b === "6") return 80
  if (b === "5") return 80
  return 20
}

function capHint(radio) {
  var caps = radioCaps(radio)
  var bands = caps.bands || radioBands(radio)
  var bits = []
  if (caps.eht) bits.push("Wi-Fi 7")
  else if (caps.he) bits.push(bands.indexOf("6") >= 0 ? "Wi-Fi 6E" : "Wi-Fi 6")
  else if (caps.vht) bits.push("Wi-Fi 5")
  else if (caps.ht) bits.push("Wi-Fi 4")
  var maxW = 0
  var mw = caps.max_width || {}
  var lw = caps.learned_width || {}
  for (var i = 0; i < bands.length; i++) {
    var b = bands[i]
    var n = Math.max(Number(mw[b] || 0), Number(lw[b] || 0))
    if (n > maxW) maxW = n
  }
  if (maxW > 0) bits.push(maxW + " MHz")
  return bits.join(" · ")
}

function radioMeta(radio) {
  if (!radio) return ""
  var parts = []
  parts.push(busLabel(radio.bus))
  if (radio.phy) parts.push(radio.phy)
  if (radio.driver) parts.push(radio.driver)
  var hint = capHint(radio)
  if (hint) parts.push(hint)
  return parts.join(" · ")
}

function radioDetail(radio) {
  if (!radio) return ""
  if (radio.capturing) {
    var pkts = Number(radio.capture_packets || 0)
    if (radio.role === "active")
      return pkts > 0 ? pkts + " beacons" : "survey"
    return pkts > 0 ? pkts + " pkts" : "capturing"
  }
  if ((radio.role === "hopper" || radio.role === "active") && radio.hop_channels && radio.hop_channels.length)
    return "scan " + (radio.hop_band || radio.band || "") + " GHz"
  if (radio.role === "monitor")
    return radio.channel ? ("mon ch" + radio.channel) : "monitor"
  if (radio.ssid) return radio.ssid
  if (radio.station_iface) return radio.station_iface
  return radio.phy || ""
}

function radioChannelText(radio) {
  if (!radio) return ""
  if (isDisabled(radio)) return "Disabled"
  if ((radio.role === "hopper" || radio.role === "active") && radio.hop_channels && radio.hop_channels.length) {
    var hopBand = radio.hop_band || radio.band || ""
    var n = radio.hop_channels.length
    return "Scanning " + (hopBand ? bandLabel(hopBand) : (n + " channels")) + " · " + n + " ch"
  }
  if (radio.role === "active")
    return "Scan ch" + (radio.channel || "?") + (radio.band ? (" · " + bandLabel(radio.band)) : "")
  var channel = radio.channel || 0
  var width = radio.width || 0
  if (!channel) return radio.role === "monitor" ? "Monitor, no channel" : (radio.role === "active" ? "Active scan, no channel" : "No channel")
  var text = "Channel " + channel
  if (radio.band) text += " · " + bandLabel(radio.band)
  else if (radio.freq >= 5925) text += " · 6 GHz"
  if (radio.freq) text += " · " + Math.round(radio.freq) + " MHz"
  if (width) text += " · " + width + " MHz"
  return text
}

function psc6() {
  return [5, 21, 37, 53, 69, 85, 101, 117, 133, 149, 165]
}

function channels24() {
  return [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
}

function radio24(radio) {
  var fallback = channels24()
  var chans = (radio && radio.channels) || []
  if (!chans.length) return fallback
  var seen = {}
  var enabled = []
  for (var i = 0; i < chans.length; i++) {
    var c = chans[i]
    if (!c || c.disabled) continue
    if (c.band && c.band !== "2.4") continue
    var ch = Number(c.channel)
    if (ch < 1 || ch > 14 || seen[ch]) continue
    seen[ch] = true
    enabled.push(ch)
  }
  if (!enabled.length) return fallback
  enabled.sort(function(a, b) { return a - b })
  return enabled
}

function dfs5() {
  // US UNII-2A + UNII-2C radar (DFS) 20 MHz channels.
  return [52, 56, 60, 64, 100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144]
}

function radioDfs5(radio) {
  var radar = (radioCaps(radio).radar || {})["5"]
  if (radar && radar.length >= 2) return radar.slice()
  var list = dfs5()
  var enabled = capChannels(radio, "5")
  if (!enabled.length) {
    var chans = (radio && radio.channels) || []
    if (!chans.length) return list
    var map = {}
    for (var i = 0; i < chans.length; i++) {
      var c = chans[i]
      if (!c || c.disabled) continue
      if (c.band && c.band !== "5") continue
      map[Number(c.channel)] = true
    }
    var filtered = []
    for (var j = 0; j < list.length; j++) if (map[list[j]]) filtered.push(list[j])
    return filtered.length >= 2 ? filtered : list
  }
  var out = []
  for (var k = 0; k < list.length; k++) if (enabled.indexOf(list[k]) >= 0) out.push(list[k])
  return out.length >= 2 ? out : list
}

function channelsFromPhyList(radio, band) {
  var chans = (radio && radio.channels) || []
  var out = []
  var seen = {}
  for (var i = 0; i < chans.length; i++) {
    var c = chans[i]
    if (!c || c.disabled) continue
    if (c.band && c.band !== band) continue
    var ch = Number(c.channel)
    if (!ch || seen[ch]) continue
    if (!c.band) {
      if (band === "2.4" && (ch < 1 || ch > 14)) continue
      if (band === "5" && (ch < 32 || ch > 196)) continue
      if (band === "6" && ch > 233) continue
    }
    seen[ch] = true
    out.push(ch)
  }
  out.sort(function(a, b) { return a - b })
  return out
}

function radio5(radio) {
  var fromCaps = (radioCaps(radio).channels || {})["5"]
  if (fromCaps && fromCaps.length) return fromCaps.slice()
  var fromPhy = channelsFromPhyList(radio, "5")
  if (fromPhy.length) return fromPhy
  return [36, 40, 44, 48].concat(dfs5()).concat([149, 153, 157, 161, 165])
}

function radio6(radio) {
  var fromCaps = (radioCaps(radio).channels || {})["6"]
  if (fromCaps && fromCaps.length) return fromCaps.slice()
  var fromPhy = channelsFromPhyList(radio, "6")
  if (fromPhy.length) return fromPhy
  return psc6()
}

function radioPsc6(radio) {
  var enabled = capChannels(radio, "6")
  var psc = psc6()
  if (!enabled.length) return psc.slice(0, 5)
  var out = []
  for (var i = 0; i < psc.length; i++) if (enabled.indexOf(psc[i]) >= 0) out.push(psc[i])
  return out.length >= 2 ? out : psc.slice(0, 5)
}

function intersectChannels(list, enabled) {
  if (!enabled || !enabled.length) return list.slice()
  var out = []
  for (var i = 0; i < list.length; i++) if (enabled.indexOf(list[i]) >= 0) out.push(list[i])
  return out
}

function radioBands(radio) {
  var bands = (radio && radio.bands) || []
  return bands
}

function defaultBand(radio) {
  var bands = radioBands(radio)
  if (radio && radio.band && bands.indexOf(radio.band) >= 0) return radio.band
  if (bands.indexOf("6") >= 0) return "6"
  if (bands.indexOf("5") >= 0) return "5"
  if (bands.indexOf("2.4") >= 0) return "2.4"
  return ""
}

function preferredChannel(radio, band) {
  var focus = band || defaultBand(radio)
  if (!focus) return { channel: (radio && radio.channel) || 0, band: (radio && radio.band) || "" }
  var list = capChannels(radio, focus)
  function pick(preferred, fallback) {
    if (list && list.indexOf(preferred) >= 0) return preferred
    if (list && list.length) return list[0]
    return fallback
  }
  if (focus === "6") {
    var psc = radioPsc6(radio)
    if (psc.indexOf(69) >= 0) return { channel: 69, band: "6" }
    if (psc.length) return { channel: psc[0], band: "6" }
    return { channel: pick(69, 5), band: "6" }
  }
  if (focus === "5") return { channel: pick(36, 36), band: "5" }
  if (focus === "2.4") return { channel: pick(6, 6), band: "2.4" }
  if (list && list.length) return { channel: list[0], band: focus }
  return { channel: (radio && radio.channel) || 0, band: focus }
}

function isUplink(radio) {
  return !!(radio && radio.uplink)
}

function isLabRadio(radio) {
  return !!(radio && (radio.lab || radio.bus === "usb"))
}

function labRadio(status) {
  var radios = (status && status.radios) || []
  for (var i = 0; i < radios.length; i++) if (isLabRadio(radios[i])) return radios[i]
  return null
}

function uplinkRadio(status) {
  var radios = (status && status.radios) || []
  for (var i = 0; i < radios.length; i++) if (isUplink(radios[i])) return radios[i]
  return null
}

function channelPresets(radio, band) {
  var presets = []
  var bands = radioBands(radio)
  var focus = band || defaultBand(radio)
  function add(ch, b) {
    presets.push({ channel: ch, band: b, label: String(ch) })
  }
  if (focus === "2.4" && bands.indexOf("2.4") >= 0) {
    var two = capChannels(radio, "2.4")
    for (var t = 0; t < two.length; t++) add(two[t], "2.4")
  } else if (focus === "5" && bands.indexOf("5") >= 0) {
    var five = capChannels(radio, "5")
    for (var f = 0; f < five.length; f++) add(five[f], "5")
  } else if (focus === "6" && bands.indexOf("6") >= 0) {
    var six = capChannels(radio, "6")
    for (var i = 0; i < six.length; i++) add(six[i], "6")
  }
  if (radio && radio.channel && (radio.band || focus) === focus) {
    var exists = false
    for (var p = 0; p < presets.length; p++) if (presets[p].channel === radio.channel) exists = true
    if (!exists && radio.channel) add(radio.channel, focus)
  }
  return presets
}

function scanChannels(radio, band) {
  var focus = band || defaultBand(radio)
  if (focus === "6") return radioPsc6(radio)
  return capChannels(radio, focus)
}

function scanningBand(radio, band) {
  if (!radio || (radio.role !== "hopper" && radio.role !== "active")) return false
  if (!(radio.hop_channels && radio.hop_channels.length) && radio.role !== "active") return false
  return String(radio.hop_band || radio.band || "") === String(band || "")
}

function widthOptions(radio, band) {
  var b = band || defaultBand(radio)
  var max = capMaxWidth(radio, b)
  var options = [20]
  if (max >= 40) options.push(40)
  if (max >= 80) options.push(80)
  if (max >= 160) options.push(160)
  if (max >= 320) options.push(320)
  return options
}

function parkWidth(radio, band) {
  var b = String(band || (radio && radio.band) || "")
  var max = capMaxWidth(radio, b)
  var w = Number(radio && radio.width) || 0
  var steps = [320, 160, 80, 40, 20]
  for (var i = 0; i < steps.length; i++) {
    if (w >= steps[i] && max >= steps[i]) return steps[i]
  }
  if (b === "6" && max >= 80) return 80
  if (max >= 40 && b === "2.4") return 20
  return Math.min(20, max) || 20
}

function rssiDesc(a, b) {
  var ar = a.rssi === undefined || a.rssi === null ? -999 : a.rssi
  var br = b.rssi === undefined || b.rssi === null ? -999 : b.rssi
  return br - ar
}

function airBand(row) {
  if (!row) return ""
  var band = String(row.band || "")
  if (band === "2.4" || band === "5" || band === "6") return band
  var freq = Number(row.freq)
  if (isFinite(freq) && freq > 0) {
    if (freq >= 5925 && freq < 7125) return "6"
    if (freq >= 4900 && freq < 5925) return "5"
    if (freq >= 2400 && freq < 2500) return "2.4"
  }
  var ch = Number(row.channel)
  var width = Number(row.width)
  if (ch >= 32 && ch <= 196) return "5"
  if (ch > 196 && ch <= 233) return "6"
  if (ch >= 1 && ch <= 14 && width >= 80) return "6"
  if (ch >= 1 && ch <= 14) return "2.4"
  return ""
}

function airBandTitle(band, count) {
  var name = band === "2.4" ? "2.4 GHZ" : (band === "5" ? "5 GHZ" : (band === "6" ? "6 GHZ" : "OTHER"))
  var n = Number(count)
  if (!isFinite(n) || n < 0) n = 0
  return name + " · " + Math.round(n)
}

function airView(status, perBandLimit) {
  var rows = Array.isArray(status && status.air) ? status.air.slice() : []
  var buckets = { "2.4": [], "5": [], "6": [], "": [] }
  for (var i = 0; i < rows.length; i++) {
    var b = airBand(rows[i])
    if (!buckets[b]) buckets[b] = []
    buckets[b].push(rows[i])
  }
  var cap = parseInt(perBandLimit, 10)
  if (!isFinite(cap) || cap < 0) cap = 0
  var order = ["2.4", "5", "6", ""]
  var groups = []
  var flat = []
  var items = []
  for (var o = 0; o < order.length; o++) {
    var band = order[o]
    var list = buckets[band] || []
    if (!list.length) continue
    list.sort(rssiDesc)
    if (cap > 0) list = list.slice(0, cap)
    groups.push({ band: band, rows: list })
    var title = airBandTitle(band, list.length)
    for (var j = 0; j < list.length; j++) {
      flat.push(list[j])
      items.push({
        band: band,
        section: j === 0 ? title : "",
        bss: list[j]
      })
    }
  }
  return { groups: groups, rows: flat, items: items }
}

function airBandRows(status, band) {
  var rows = Array.isArray(status && status.air) ? status.air.slice() : []
  var want = String(band || "")
  var out = []
  for (var i = 0; i < rows.length; i++) {
    if (airBand(rows[i]) === want) out.push(rows[i])
  }
  out.sort(rssiDesc)
  return out
}

function airRows(status, limit) {
  return airView(status, limit).rows
}

function clientRows(status, limit) {
  var rows = Array.isArray(status && status.clients) ? status.clients.slice() : []
  rows.sort(function(a, b) {
    return (b.last_seen || 0) - (a.last_seen || 0)
  })
  return rows.slice(0, Math.max(1, parseInt(limit, 10) || 8))
}

function ssidLabel(row) {
  if (!row) return "(hidden)"
  var raw = row.ssid
  if (raw === undefined || raw === null) raw = ""
  var ssid = String(raw)
  var cleaned = ""
  for (var i = 0; i < ssid.length && cleaned.length < 32; i++) {
    var c = ssid.charCodeAt(i)
    if (c < 32 || c === 127) continue
    cleaned += ssid.charAt(i)
  }
  if (!cleaned) return "(hidden)"
  return cleaned
}

function captureName(path) {
  var value = String(path || "")
  var parts = value.split("/")
  return parts[parts.length - 1] || value
}

function relativeTime(mtime, now) {
  var ts = Number(mtime)
  if (!isFinite(ts) || ts <= 0) return ""
  if (ts > 1e12) ts = Math.floor(ts / 1000)
  var seconds = Math.max(0, Math.floor((Number(now) || Date.now()) / 1000 - ts))
  if (seconds < 10) return "just now"
  if (seconds < 60) return seconds + "s ago"
  if (seconds < 3600) return Math.floor(seconds / 60) + "m ago"
  if (seconds < 86400) return Math.floor(seconds / 3600) + "h ago"
  return Math.floor(seconds / 86400) + "d ago"
}

function barBadge(status) {
  var radios = (status && status.radios) || []
  return radios.length
}

function barMode(status) {
  if ((status && status.capture_count) > 0) return "capture"
  if ((status && status.monitor_count) > 0) return "monitor"
  if ((status && status.radio_count) > 0) return "idle"
  return "empty"
}

function heroTitle(status) {
  var count = (status && status.radio_count) || 0
  if (count === 0) return "Radio Lab"
  if (count === 1) return "1 radio"
  return count + " radios"
}

function heroDetail(status) {
  if (!status) return ""
  if (status.capture_count > 0) return status.capture_count + " cap"
  if (status.monitor_count > 0) return status.monitor_count + " mon"
  return helperState(status) === "running" ? "armed" : ""
}

if (typeof module !== "undefined") {
  module.exports = {
    emptyStatus: emptyStatus,
    parseStatus: parseStatus,
    helperState: helperState,
    helperReady: helperReady,
    formatBytes: formatBytes,
    formatRssi: formatRssi,
    formatWidth: formatWidth,
    bandLabel: bandLabel,
    roleLabel: roleLabel,
    radioRoleLabel: radioRoleLabel,
    isDisabled: isDisabled,
    busLabel: busLabel,
    radioTitle: radioTitle,
    radioMeta: radioMeta,
    radioDetail: radioDetail,
    radioChannelText: radioChannelText,
    channelPresets: channelPresets,
    scanChannels: scanChannels,
    scanningBand: scanningBand,
    channels24: channels24,
    radio24: radio24,
    preferredChannel: preferredChannel,
    defaultBand: defaultBand,
    capHint: capHint,
    capMaxWidth: capMaxWidth,
    capChannels: capChannels,
    widthOptions: widthOptions,
    parkWidth: parkWidth,
    airBand: airBand,
    airBandTitle: airBandTitle,
    airBandRows: airBandRows,
    airView: airView,
    airRows: airRows,
    clientRows: clientRows,
    ssidLabel: ssidLabel,
    captureName: captureName,
    relativeTime: relativeTime,
    barBadge: barBadge,
    barMode: barMode,
    heroTitle: heroTitle,
    heroDetail: heroDetail
  }
}
