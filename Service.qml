import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property string helperPath: String(Qt.resolvedUrl("status.py")).replace("file://", "")

  property bool installed: false
  property bool running: false
  property bool pausedAll: false
  property bool syncing: false
  property bool errorState: false

  // Optimistic pause state so the switch reacts the instant you click, rather
  // than waiting for the API round trip. _desired is -1 while we just follow
  // the observed state, or 0/1 while a pause/resume is catching up.
  property int _desired: -1
  readonly property bool active: _desired === -1 ? (running && !pausedAll) : (_desired === 1)
  property bool refreshing: false
  property string statusText: "Checking…"
  property string myName: ""
  property double uptimeSec: 0
  property string apiBase: ""
  property var devices: []
  property var folders: []
  property string actionStatus: ""
  property string lastError: ""

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 10, 5, 3600)
  readonly property bool busy: statusProcess.running || controlProcess.running || guiProcess.running

  property string _statusOutput: ""
  property string _statusError: ""
  property string _controlOutput: ""
  property string _controlError: ""
  property string _guiOutput: ""
  property string _guiError: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function refresh() {
    if (statusProcess.running) return
    _statusOutput = ""
    _statusError = ""
    refreshing = true
    statusProcess.command = ["python3", helperPath, "status"]
    statusProcess.running = true
    // The helper only exits when done, so a poll is skipped whenever its
    // process is still alive. Reap a wedged poll so the next tick starts
    // clean instead of starving the panel forever.
    if (!pollWatchdog.running) pollWatchdog.start()
  }

  function applyStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (!parsed.ok) {
      installed = parsed.installed === true
      running = parsed.running === true
      pausedAll = false
      _desired = -1
      syncing = false
      errorState = false
      statusText = installed ? "Not running" : "Not installed"
      lastError = parsed.lastError || "Failed to read Syncthing status"
      return
    }
    installed = parsed.installed === true
    running = parsed.running === true
    pausedAll = parsed.pausedAll === true
    if (_desired !== -1 && (running && !pausedAll) === (_desired === 1)) _desired = -1
    syncing = parsed.syncing === true
    errorState = parsed.errorState === true
    myName = String(parsed.myName || "")
    uptimeSec = Number(parsed.uptime || 0)
    if (String(parsed.api || "") !== "") apiBase = String(parsed.api)
    devices = parsed.devices || []
    folders = parsed.folders || []
    if (!installed) statusText = "Not installed"
    else if (!running) statusText = "Not running"
    else if (pausedAll) statusText = "Paused"
    else if (syncing) statusText = "Syncing"
    else statusText = "Up to date"
    lastError = ""
  }

  function elideStatus(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 140 ? value.substring(0, 137) + "…" : value
  }

  function pauseAll() {
    runControl("pause", 0)
  }

  function resumeAll() {
    runControl("resume", 1)
  }

  function toggleRunning() {
    if (active) pauseAll()
    else resumeAll()
  }

  function rescanAll() {
    runScan(null, "")
  }

  function rescanFolder(folderId, folderLabel) {
    runScan(folderId, folderLabel)
  }

  function runScan(folderId, folderLabel) {
    if (!running || controlProcess.running) return
    _controlOutput = ""
    _controlError = ""
    actionStatus = folderId
        ? "Rescanning " + (folderLabel || folderId) + "…"
        : "Rescanning all folders…"
    var command = ["python3", helperPath, "scan"]
    if (folderId) command.push(folderId)
    controlProcess.command = command
    controlProcess.running = true
    actionStatusTimer.restart()
  }

  function runControl(command, desired) {
    // No progress status here — the switch already conveys the optimistic
    // pause/resume; only surface a message if the command fails.
    if (!running || controlProcess.running) return
    _desired = desired
    _controlOutput = ""
    _controlError = ""
    controlProcess.command = ["python3", helperPath, command]
    controlProcess.running = true
  }

  function openWebGui() {
    if (apiBase !== "") {
      Quickshell.execDetached(["omarchy-launch-browser", apiBase])
      return
    }
    if (guiProcess.running) return
    _controlOutput = ""
    _controlError = ""
    guiProcess.command = ["python3", helperPath, "gui-url"]
    guiProcess.running = true
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: delayedRefresh
    interval: 1000
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: actionStatusTimer
    interval: 2200
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Timer {
    // Syncthing takes a moment to settle after pause/resume/scan, so re-poll
    // a few times to reflect the new state without waiting for the next
    // periodic refresh.
    id: settleTimer
    property int ticks: 0
    interval: 1500
    repeat: true
    running: false
    onTriggered: {
      settleTimer.ticks += 1
      root.refresh()
      if (settleTimer.ticks >= 4) {
        settleTimer.ticks = 0
        settleTimer.running = false
        root._desired = -1
      }
    }
  }

  Timer {
    id: pollWatchdog
    interval: 15000
    repeat: false
    onTriggered: if (statusProcess.running) statusProcess.running = false
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      root.refreshing = false
      var stdout = String(statusStdout.text || root._statusOutput || "")
      var stderr = String(statusStderr.text || root._statusError || "")
      if (exitCode === 0) root.applyStatus(stdout)
      else {
        root.running = false
        root.pausedAll = false
        root._desired = -1
        root.syncing = false
        root.errorState = false
        root.statusText = "Not running"
        root.lastError = root.elideStatus(stderr || stdout || "Could not read Syncthing status")
      }
    }
  }

  Process {
    id: controlProcess
    running: false
    command: []
    stdout: StdioCollector { id: controlStdout; waitForEnd: true; onStreamFinished: root._controlOutput = text }
    stderr: StdioCollector { id: controlStderr; waitForEnd: true; onStreamFinished: root._controlError = text }
    onExited: function(exitCode) {
      var stdout = String(controlStdout.text || root._controlOutput || "")
      var stderr = String(controlStderr.text || root._controlError || "")
      // The helper reports failures as {"ok": false} with exit code 0, so the
      // stdout payload decides success — not the exit code alone.
      var parsed = exitCode === 0 ? Model.parseStatus(stdout) : null
      if (exitCode !== 0 || !parsed.ok) {
        root._desired = -1
        root.lastError = root.elideStatus(
          (parsed && parsed.lastError) || stderr || stdout || "Syncthing command failed"
        )
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
      }
      settleTimer.ticks = 0
      settleTimer.restart()
      delayedRefresh.restart()
    }
  }

  Process {
    id: guiProcess
    running: false
    command: []
    stdout: StdioCollector { id: guiStdout; waitForEnd: true; onStreamFinished: root._guiOutput = text }
    stderr: StdioCollector { id: guiStderr; waitForEnd: true; onStreamFinished: root._guiError = text }
    onExited: function(exitCode) {
      var stdout = String(guiStdout.text || root._guiOutput || "")
      var stderr = String(guiStderr.text || root._guiError || "")
      var parsed = exitCode === 0 ? Model.parseStatus(stdout) : null
      var url = String((parsed && parsed.url) || "")
      if (exitCode === 0 && parsed.ok && url !== "") {
        root.apiBase = url
        Quickshell.execDetached(["omarchy-launch-browser", url])
      } else {
        root.lastError = root.elideStatus(
          (parsed && parsed.lastError) || stderr || stdout || "Could not find the Syncthing GUI"
        )
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      }
    }
  }
}
