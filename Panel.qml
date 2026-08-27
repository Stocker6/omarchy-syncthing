import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "lee.syncthing"
  ipcTarget: "lee.syncthing"
  manageIpc: false

  property string focusSection: "header"
  property int rowIndex: 0
  property bool cursorActive: false
  property int phraseIndex: 0

  readonly property var activePhrases: [
    "Trading bytes",
    "Ferrying files",
    "Balancing blocks",
    "Minding folders",
    "Syncing silently",
    "Copying carefully",
    "Weaving folders",
    "Moving moments"
  ]
  readonly property string heroPhraseText: activePhrases[phraseIndex % activePhrases.length]
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color iconColor: syncthing.active ? foreground : dim
  readonly property string toggleHint: syncthing.active ? "Pause all devices" : "Resume all devices"
  readonly property color barIconColor: syncthing.active ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property bool headerHasCursor: cursorActive && focusSection === "header" && syncthing.running
  readonly property int connectedCount: {
    var count = 0
    for (var i = 0; i < syncthing.devices.length; i++) {
      if (syncthing.devices[i].connected) count++
    }
    return count
  }
  readonly property int problemFolders: {
    var count = 0
    for (var i = 0; i < syncthing.folders.length; i++) {
      if (Model.folderHasProblem(syncthing.folders[i])) count++
    }
    return count
  }
  readonly property string heroMeta: {
    if (!syncthing.running) return syncthing.installed ? "Syncthing is not running" : "Syncthing is not installed"
    if (syncthing.pausedAll) return "Syncing paused"
    if (syncthing.syncing) return heroPhraseText
    if (problemFolders > 0) return problemFolders + (problemFolders === 1 ? " folder needs attention" : " folders need attention")
    return "Up to date"
  }

  function buildRows() {
    var rows = []
    var index = 0
    rows.push({ rowIndex: index++, action: "gui" })
    rows.push({ rowIndex: index++, action: "scan" })
    if (syncthing.devices.length > 0) rows.push({ header: "DEVICES" })
    for (var d = 0; d < syncthing.devices.length; d++) {
      rows.push({ rowIndex: index++, device: syncthing.devices[d] })
    }
    if (syncthing.folders.length > 0) rows.push({ header: "FOLDERS" })
    for (var f = 0; f < syncthing.folders.length; f++) {
      rows.push({ rowIndex: index++, folder: syncthing.folders[f] })
    }
    return rows
  }

  readonly property var panelRows: buildRows()

  function actionableRowCount() {
    return 2 + syncthing.devices.length + syncthing.folders.length
  }

  function ensureCursor() {
    if (rowIndex >= actionableRowCount()) rowIndex = Math.max(0, actionableRowCount() - 1)
    if (rowIndex < 0) rowIndex = 0
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy === 0) return
    if (focusSection === "header") {
      if (dy > 0) {
        focusSection = "rows"
        rowIndex = 0
        scrollCursorIntoView()
      }
      return
    }
    if (focusSection === "rows") {
      if (dy < 0 && rowIndex === 0) {
        setHeaderCursor()
        return
      }
      rowIndex = Math.max(0, Math.min(actionableRowCount() - 1, rowIndex + dy))
      scrollCursorIntoView()
    }
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
    if (panelFlick) panelFlick.contentY = 0
  }

  function setRowCursor(index) {
    cursorActive = true
    focusSection = "rows"
    rowIndex = index
    scrollCursorIntoView()
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "header") toggleRunning()
    else activateRow(findRow(rowIndex))
  }

  function findRow(index) {
    for (var i = 0; i < panelRows.length; i++) {
      if (panelRows[i].rowIndex === index) return panelRows[i]
    }
    return null
  }

  function activateRow(row) {
    if (!row) return
    if (row.action === "gui" || row.device) syncthing.openWebGui()
    else if (row.action === "scan") syncthing.rescanAll()
    else if (row.folder) syncthing.rescanFolder(String(row.folder.id || ""), String(row.folder.label || ""))
  }

  function toggleRunning() {
    if (syncthing.running && !syncthing.busy) syncthing.toggleRunning()
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollCursorIntoView() {
    if (focusSection !== "rows" || !rowColumn) return
    for (var i = 0; i < rowColumn.children.length; i++) {
      var child = rowColumn.children[i]
      if (child && child.rowIndex === rowIndex) {
        scrollItemIntoView(child)
        return
      }
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    if (panelFlick) panelFlick.contentY = 0
    syncthing.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onRowIndexChanged: scrollCursorIntoView()

  Service {
    id: syncthing
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { syncthing.refresh(); return "ok" }
    function status(): string { return syncthing.statusText }
    function openGui(): string { syncthing.openWebGui(); return "ok" }
    function pause(): string { syncthing.pauseAll(); return "ok" }
    function resume(): string { syncthing.resumeAll(); return "ok" }
    function scan(): string { syncthing.rescanAll(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        SyncthingIcon {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: root.barIconColor
          badgeColor: root.urgent
          crossed: !syncthing.running
          warning: syncthing.errorState
          spinning: syncthing.syncing && !syncthing.pausedAll
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) syncthing.refresh()
      else if (buttonCode === Qt.MiddleButton) syncthing.openWebGui()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "g" || t === "G") syncthing.openWebGui()
        else if (t === "p" || t === "P") root.toggleRunning()
        else if (t === "r" || t === "R") syncthing.refresh()
        else if (t === "s" || t === "S") syncthing.rescanAll()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            visible: syncthing.running
            width: parent.width
            implicitHeight: hero.implicitHeight
            // Exposed for the hero's trailingControl, whose `root` resolves to
            // PanelHero (not this Panel) — reach panel state via `header`.
            readonly property bool ringVisible: root.headerHasCursor
            function focusHero() { root.setHeaderCursor() }

            PanelHero {
              id: hero
              width: parent.width
              title: syncthing.myName !== "" ? syncthing.myName : "Syncthing"
              meta: root.heroMeta
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: syncthing.active ? 1.0 : 0.5
              // Status only — the switch owns toggling, mouse and keyboard alike.
              iconComponent: Component {
                SyncthingIcon {
                  iconSize: Style.font.display
                  color: root.iconColor
                  badgeColor: root.urgent
                  warning: syncthing.errorState
                  spinning: syncthing.syncing && !syncthing.pausedAll
                }
              }

              // Compact pause/resume switch on the trailing edge of the hero.
              // The service already flips `active` optimistically, so the knob
              // throws the instant you click it.
              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  checked: syncthing.active
                  busy: syncthing.busy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: root.toggleRunning()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: root.toggleHint
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            visible: !syncthing.running
            width: parent.width
            text: syncthing.installed
                ? "Syncthing is not running. Start it with:\nsystemctl --user start syncthing"
                : "Syncthing is not installed."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            visible: syncthing.actionStatus !== "" || syncthing.lastError !== ""
            width: parent.width
            text: syncthing.actionStatus !== "" ? syncthing.actionStatus : syncthing.lastError
            color: syncthing.lastError !== "" && syncthing.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            visible: syncthing.running
            width: parent.width
            spacing: Style.spacing.labelGap

            InfoPair { label: "Device"; value: syncthing.myName !== "" ? syncthing.myName : "This device" }
            InfoPair { label: "Uptime"; value: Model.uptimeText(syncthing.uptimeSec) }
            InfoPair { label: "Devices"; value: root.connectedCount + " of " + syncthing.devices.length + " connected" }
            InfoPair { label: "Folders"; value: syncthing.folders.length > 0 ? String(syncthing.folders.length) : "None" }
          }

          PanelSeparator {
            foreground: root.foreground
          }

          Column {
            id: rowColumn
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.panelRows

              PanelRow {
                required property var modelData
                width: rowColumn.width
                row: modelData
              }
            }
          }
        }
      }
    }
  }

  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && syncthing.running && syncthing.syncing && !syncthing.pausedAll
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
    }
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  component PanelRow: CursorSurface {
    id: panelRow
    property var row: null
    readonly property bool isHeader: row && row.header !== undefined
    readonly property int rowIndex: row && row.rowIndex !== undefined ? row.rowIndex : -1
    hasCursor: root.cursorActive && root.focusSection === "rows" && root.rowIndex === rowIndex
    readonly property string rowGlyph: {
      if (!row) return ""
      if (row.action === "gui") return "󰖟"
      if (row.action === "scan") return "󰑐"
      if (row.device) return Model.deviceGlyph(row.device)
      if (row.folder) return Model.folderStateGlyph(row.folder)
      return ""
    }
    readonly property string rowTitle: {
      if (!row) return ""
      if (row.action === "gui") return "Open Web GUI"
      if (row.action === "scan") return "Rescan All Folders"
      if (row.device) return String(row.device.name || "Unknown")
      if (row.folder) return String(row.folder.label || row.folder.id || "Folder")
      return ""
    }
    readonly property string rowMeta: {
      if (!row) return ""
      if (row.action === "gui") return "Manage folders and devices in the browser"
      if (row.action === "scan") return "Trigger an incremental scan now"
      if (row.device) return Model.deviceMetaText(row.device)
      if (row.folder) return Model.folderMetaText(row.folder)
      return ""
    }
    readonly property bool rowProblem: row && row.folder ? Model.folderHasProblem(row.folder) : false

    visible: true
    height: isHeader ? headerLabel.implicitHeight + Style.space(14) : rowInner.implicitHeight + Style.spacing.rowPaddingX
    implicitHeight: height

    foreground: root.foreground

    PanelSectionHeader {
      id: headerLabel
      visible: panelRow.isHeader
      width: parent.width
      text: panelRow.row ? String(panelRow.row.header) : ""
      foreground: root.foreground
      fontFamily: root.fontFamily
      anchors.verticalCenter: parent.verticalCenter
    }

    MouseArea {
      visible: !panelRow.isHeader
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (panelRow.rowIndex >= 0) root.setRowCursor(panelRow.rowIndex)
      onClicked: root.activateRow(panelRow.row)
    }

    RowLayout {
      id: rowInner
      visible: !panelRow.isHeader
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: panelRow.rowGlyph
        visible: text !== ""
        color: panelRow.rowProblem ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: panelRow.rowTitle
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: panelRow.rowMeta
          visible: text !== ""
          color: panelRow.rowProblem ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
  }
}
