import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property var status: Model.emptyStatus()
  property bool refreshing: false
  property bool busy: statusProc.running || actionProc.running || helperProc.running
  property string lastError: ""
  property string actionStatus: ""
  property string pendingPhy: ""
  property string pendingKind: ""
  property bool stealArmed: false
  property string stealPhy: ""
  property string stealKind: ""
  property var stealArgs: []

  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/patrick.radio-lab"
  readonly property string ctl: pluginDir + "/bin/wnic-ctl"
  readonly property string installer: pluginDir + "/bin/install.sh"
  readonly property string helperBin: "/usr/local/lib/radio-lab/wnicd"
  readonly property int refreshIntervalSec: {
    var n = parseInt(String(settings && settings.refreshIntervalSec != null ? settings.refreshIntervalSec : 2), 10)
    if (!isFinite(n)) n = 2
    return Math.max(1, Math.min(15, n))
  }
  readonly property bool helperReady: Model.helperReady(status)
  readonly property string helperState: Model.helperState(status)
  readonly property var radios: status.radios || []
  readonly property var air: Model.airRows(status)
  readonly property var air24: Model.airBandRows(status, "2.4")
  readonly property var air5: Model.airBandRows(status, "5")
  readonly property var air6: Model.airBandRows(status, "6")
  readonly property var clients: Model.clientRows(status, 8)
  readonly property var captures: status.captures || []
  readonly property string captureDir: status.capture_dir || (Quickshell.env("HOME") + "/radio-lab/captures")
  readonly property int radioCount: status.radio_count || radios.length
  readonly property int monitorCount: status.monitor_count || 0
  readonly property int captureCount: status.capture_count || 0
  readonly property string barMode: Model.barMode(status)

  function parseAndApply(raw) {
    var next = Model.parseStatus(raw)
    if (next && next.radios) {
      status = next
      if (next.error) lastError = next.error
      else if (next.ok !== false) lastError = lastError && pendingKind ? lastError : ""
    }
  }

  function refresh() {
    if (statusProc.running) return
    refreshing = true
    statusProc.running = true
  }

  function runCtl(args) {
    if (actionProc.running) return
    lastError = ""
    actionProc.command = [ctl].concat(args)
    actionProc.running = true
  }

  function monitorOn(phy, channel, width, steal, band) {
    pendingPhy = phy
    pendingKind = "monitor"
    var args = ["monitor-on", phy, "--width", String(width || 20)]
    if (channel) args.push("--channel", String(channel))
    if (band) args.push("--band", String(band))
    if (steal) args.push("--steal")
    runCtl(args)
  }

  function monitorOff(phy) {
    pendingPhy = phy
    pendingKind = "restore"
    runCtl(["monitor-off", phy])
  }

  function setChannel(phy, channel, width, band) {
    pendingPhy = phy
    pendingKind = "channel"
    var args = ["set-channel", phy, String(channel), "--width", String(width || 20)]
    if (band) args.push("--band", String(band))
    runCtl(args)
  }

  function scanStart(phy, band, channels) {
    pendingPhy = phy
    pendingKind = "scan"
    var args = ["scan-start", phy, "--channels", (channels || []).join(",")]
    if (band) args.push("--band", String(band))
    runCtl(args)
  }

  function scanStop(phy) {
    pendingPhy = phy
    pendingKind = "scan-stop"
    runCtl(["scan-stop", phy])
  }

  function captureStart(phy, steal, channel, band) {
    pendingPhy = phy
    pendingKind = "capture"
    var args = ["capture-start", phy]
    if (steal) args.push("--steal")
    if (channel) args.push("--channel", String(channel))
    if (band) args.push("--band", String(band))
    runCtl(args)
  }

  function captureStop(phy) {
    pendingPhy = phy
    pendingKind = "capture-stop"
    runCtl(["capture-stop", phy])
  }

  function restore(phy) {
    monitorOff(phy)
  }

  function activeScanStart(phy, channel, band, channels) {
    pendingPhy = phy
    pendingKind = "active-scan"
    var args = ["active-scan-start", phy]
    if (channel) args.push("--channel", String(channel))
    if (band) args.push("--band", String(band))
    if (channels && channels.length) args.push("--channels", channels.join(","))
    runCtl(args)
  }

  function activeScanStop(phy) {
    pendingPhy = phy
    pendingKind = "active-scan-stop"
    runCtl(["active-scan-stop", phy])
  }

  function restoreWifi(phy) {
    pendingPhy = phy || ""
    pendingKind = "restore-wifi"
    actionStatus = phy ? ("Restoring Wi-Fi on " + phy + "…") : "Restoring Wi-Fi…"
    var args = ["restore-wifi"]
    if (phy) args.push(phy)
    runCtl(args)
  }

  function disableRadio(phy) {
    pendingPhy = phy
    pendingKind = "disable"
    actionStatus = "Disabling " + phy + "…"
    runCtl(["disable", phy])
  }

  function enableRadio(phy) {
    pendingPhy = phy
    pendingKind = "enable"
    actionStatus = "Enabling " + phy + "…"
    runCtl(["enable", phy])
  }

  function installHelper() {
    if (helperProc.running) return
    actionStatus = "Installing helper…"
    helperProc.command = ["pkexec", installer]
    helperProc.running = true
  }

  function startHelper() {
    if (helperProc.running) return
    actionStatus = "Starting helper…"
    if (helperState === "missing") {
      installHelper()
      return
    }
    helperProc.command = ["pkexec", "systemctl", "start", "wnicd"]
    helperProc.running = true
  }

  function openCaptures() {
    Quickshell.execDetached(["xdg-open", captureDir])
  }

  function openCapture(path) {
    if (!path) return
    Quickshell.execDetached(["xdg-open", path])
  }

  function handleActionOutput(raw, exitCode) {
    var text = String(raw || "").trim()
    if (!text) {
      if (exitCode !== 0) lastError = "Command failed"
      pendingPhy = ""
      pendingKind = ""
      refresh()
      return
    }
    var parsed = Model.parseStatus(text)
    if (parsed && parsed.plugin === "patrick.radio-lab" && Array.isArray(parsed.radios))
      status = parsed
    var kind = pendingKind
    if (parsed && parsed.needs_steal && pendingPhy) {
      stealPhy = pendingPhy
      stealKind = pendingKind
      stealArmed = true
      lastError = parsed.error || "This radio is the only station interface"
    } else if (parsed && parsed.ok === false) {
      lastError = parsed.error || "Command failed"
      if (parsed.error === "helper_not_running")
        lastError = "Helper is not running"
      if (kind === "restore-wifi" || kind === "disable" || kind === "enable") actionStatus = ""
    } else {
      lastError = ""
      stealArmed = false
      if (kind === "restore-wifi") {
        actionStatus = pendingPhy ? ("Wi-Fi restored on " + pendingPhy) : "Wi-Fi restored"
        actionStatusTimer.restart()
      } else if (kind === "disable") {
        actionStatus = pendingPhy ? (pendingPhy + " disabled") : "NIC disabled"
        actionStatusTimer.restart()
      } else if (kind === "enable") {
        actionStatus = pendingPhy ? (pendingPhy + " enabled") : "NIC enabled"
        actionStatusTimer.restart()
      }
    }
    pendingPhy = ""
    pendingKind = ""
    delayedRefresh.restart()
  }

  Process {
    id: statusProc
    command: [root.ctl, "status"]
    running: false
    stdout: StdioCollector { id: statusStdout; waitForEnd: true }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.refreshing = false
      var text = String(statusStdout.text || "")
      if (text) root.parseAndApply(text)
      else if (exitCode !== 0) root.lastError = String(statusStderr.text || "status failed").trim()
    }
  }

  Process {
    id: actionProc
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var stdout = String(actionStdout.text || "")
      var stderr = String(actionStderr.text || "").trim()
      if (stdout) root.handleActionOutput(stdout, exitCode)
      else {
        root.lastError = stderr || (exitCode === 0 ? "" : "Command failed")
        root.pendingPhy = ""
        root.pendingKind = ""
        root.delayedRefresh.restart()
      }
    }
  }

  Process {
    id: helperProc
    running: false
    command: []
    stdout: StdioCollector { id: helperStdout; waitForEnd: true }
    stderr: StdioCollector { id: helperStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var stderr = String(helperStderr.text || "").trim()
      var stdout = String(helperStdout.text || "").trim()
      if (exitCode === 0) {
        root.actionStatus = "Helper ready"
        root.lastError = ""
      } else {
        root.lastError = stderr || stdout || "Helper install/start failed"
        root.actionStatus = ""
      }
      actionStatusTimer.restart()
      root.delayedRefresh.restart()
      helperRamp.ticks = 0
      helperRamp.running = true
    }
  }

  Timer {
    id: delayedRefresh
    interval: 400
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: poll
    interval: Math.max(1000, root.refreshIntervalSec * 1000)
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  Timer {
    id: helperRamp
    property int ticks: 0
    interval: 800
    repeat: true
    running: false
    onTriggered: {
      ticks += 1
      root.refresh()
      if (root.helperReady || ticks >= 12) helperRamp.running = false
    }
  }

  Timer {
    id: actionStatusTimer
    interval: 2400
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Timer {
    id: watchdog
    interval: 12000
    repeat: false
    running: statusProc.running || actionProc.running
    onTriggered: {
      if (statusProc.running) statusProc.running = false
      if (actionProc.running) actionProc.running = false
    }
  }

  Component.onCompleted: refresh()
}
