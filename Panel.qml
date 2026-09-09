import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "patrick.radio-lab"
  ipcTarget: "patrick.radio-lab"
  manageIpc: false

  property string focusSection: "header"
  property int radioIndex: 0
  property int airIndex: 0
  property int captureIndex: 0
  property bool cursorActive: false
  property int phraseIndex: 0
  property int pendingChannel: 0
  property int pendingWidth: 20
  property var bandByPhy: ({})
  property var labUnlocked: ({})

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property bool headerHasCursor: cursorActive && focusSection === "header"
  readonly property var radios: {
    var list = (lab.radios || []).slice()
    list.sort(function(a, b) {
      var al = Model.isLabRadio(a) ? 0 : (Model.isUplink(a) ? 2 : 1)
      var bl = Model.isLabRadio(b) ? 0 : (Model.isUplink(b) ? 2 : 1)
      return al - bl
    })
    return list
  }
  readonly property bool listening: {
    var list = radios
    for (var i = 0; i < list.length; i++) {
      var role = list[i] && list[i].role
      if (role === "monitor" || role === "hopper" || role === "active") return true
    }
    return false
  }
  readonly property var airRows: lab.air
  readonly property var captureRows: lab.captures
  readonly property bool helperReady: lab.helperReady
  readonly property string helperState: lab.helperState
  readonly property var activePhrases: [
    "Parking radios",
    "Sweeping spectrum",
    "Bagging frames",
    "Stalking beacons",
    "Hopping channels",
    "Herding NICs",
    "Listening to air",
    "Counting SSIDs"
  ]
  readonly property string heroPhraseText: {
    if (radios.length === 0) return "No wireless NICs"
    if (!helperReady) return helperState === "missing" ? "Helper not installed" : "Helper is stopped"
    if (lab.captureCount > 0) return "Writing pcaps"
    if (lab.monitorCount > 0) return "Watching the air"
    return activePhrases[phraseIndex % activePhrases.length]
  }
  readonly property color barIconColor: {
    if (lab.barMode === "capture") return urgent
    if (lab.barMode === "empty") return dim
    return barForeground
  }
  readonly property string toggleHint: helperReady ? "Helper is armed" : (helperState === "missing" ? "Install Radio Lab helper" : "Start Radio Lab helper")

  function selectedRadio() {
    if (radios.length === 0) return null
    return radios[Math.max(0, Math.min(radioIndex, radios.length - 1))]
  }

  function bandFor(radio) {
    if (!radio) return ""
    if (bandByPhy[radio.phy]) return bandByPhy[radio.phy]
    return Model.defaultBand(radio)
  }

  function setBandFor(phy, band) {
    var next = {}
    for (var key in bandByPhy) next[key] = bandByPhy[key]
    next[phy] = band
    bandByPhy = next
  }

  function unlockPhy(phy) {
    var next = {}
    for (var key in labUnlocked) next[key] = labUnlocked[key]
    next[phy] = true
    labUnlocked = next
  }

  function isLocked(radio) {
    if (radio && radio.passive_monitor === false) return false
    return Model.isUplink(radio) && !labUnlocked[radio.phy]
  }

  function isPassive(radio) {
    if (!radio) return true
    if (radio.passive_monitor === false) return false
    if (radio.passive_monitor === true) return true
    var driver = String(radio.driver || "")
    if (driver.indexOf("rtw88") === 0 || driver.indexOf("rtl8") === 0) return false
    return true
  }

  function ensureCursor() {
    if (radioIndex >= radios.length) radioIndex = Math.max(0, radios.length - 1)
    if (airIndex >= airRows.length) airIndex = Math.max(0, airRows.length - 1)
    if (captureIndex >= captureRows.length) captureIndex = Math.max(0, captureRows.length - 1)
    if (focusSection === "radios" && radios.length === 0) focusSection = "header"
    if (focusSection === "air" && airRows.length === 0) focusSection = radios.length ? "radios" : "header"
    if (focusSection === "captures" && captureRows.length === 0) focusSection = airRows.length ? "air" : (radios.length ? "radios" : "header")
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy !== 0) {
      if (focusSection === "header") {
        if (dy > 0) focusSection = radios.length ? "radios" : (airRows.length ? "air" : "header")
      } else if (focusSection === "radios") {
        if (dy < 0) {
          if (radioIndex <= 0) focusSection = "header"
          else radioIndex--
        } else if (radioIndex < radios.length - 1) {
          radioIndex++
        } else if (airRows.length) {
          focusSection = "air"
        } else if (captureRows.length) {
          focusSection = "captures"
        }
      } else if (focusSection === "air") {
        if (dy < 0) {
          if (airIndex <= 0) focusSection = radios.length ? "radios" : "header"
          else airIndex--
        } else if (airIndex < airRows.length - 1) {
          airIndex++
        } else if (captureRows.length) {
          focusSection = "captures"
        }
      } else if (focusSection === "captures") {
        if (dy < 0) {
          if (captureIndex <= 0) focusSection = airRows.length ? "air" : (radios.length ? "radios" : "header")
          else captureIndex--
        } else if (captureIndex < captureRows.length - 1) {
          captureIndex++
        }
      }
    } else if (dx !== 0 && focusSection === "radios") {
      nudgeChannel(dx)
    }
    ensureCursor()
  }

  function nudgeChannel(dx) {
    var radio = selectedRadio()
    if (!radio || !helperReady) return
    var presets = Model.channelPresets(radio)
    if (!presets.length) return
    var idx = 0
    for (var i = 0; i < presets.length; i++) {
      if (Number(presets[i].channel) === Number(radio.channel) && String(presets[i].band) === String(radio.band || presets[i].band))
        idx = i
    }
    idx = Math.max(0, Math.min(presets.length - 1, idx + dx))
    parkOn(radio, presets[idx].channel, radio.width || 20, presets[idx].band)
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "header") {
      if (!helperReady) lab.startHelper()
      return
    }
    if (focusSection === "radios") {
      var radio = selectedRadio()
      if (radio) toggleMonitor(radio)
      return
    }
    if (focusSection === "captures") {
      var cap = captureRows[captureIndex]
      if (cap) lab.openCapture(cap.path)
    }
  }

  function toggleMonitor(radio) {
    if (!radio || lab.busy) return
    if (!isPassive(radio)) {
      if (radio.role === "active") lab.activeScanStop(radio.phy)
      else {
        var pick = defaultChannel(radio)
        lab.activeScanStart(radio.phy, pick.channel, pick.band)
      }
      return
    }
    if (isLocked(radio)) {
      requestLabUnlock(radio)
      return
    }
    if (radio.role === "monitor") lab.monitorOff(radio.phy)
    else {
      var start = defaultChannel(radio)
      lab.monitorOn(radio.phy, start.channel, Model.parkWidth(radio, start.band), false, start.band)
    }
  }

  function toggleDisable(radio) {
    if (!radio || lab.busy) return
    if (radio.disabled) lab.enableRadio(radio.phy)
    else lab.disableRadio(radio.phy)
  }

  function toggleCapture(radio) {
    if (!radio || lab.busy) return
    if (radio.capturing) {
      lab.captureStop(radio.phy)
      return
    }
    if (!isPassive(radio)) {
      var band = bandFor(radio)
      var ch = (String(radio.band || "") === String(band) && radio.channel) ? radio.channel : (band === "5" ? 36 : (band === "6" ? 69 : 6))
      lab.captureStart(radio.phy, false, ch, band)
      return
    }
    lab.captureStart(radio.phy, false)
  }

  function defaultChannel(radio) {
    var bands = radio.bands || []
    if (bands.indexOf("6") >= 0) return { channel: 69, band: "6" }
    if (bands.indexOf("2.4") >= 0) return { channel: 6, band: "2.4" }
    if (bands.indexOf("5") >= 0) return { channel: 36, band: "5" }
    return { channel: radio.channel || 1, band: radio.band || "2.4" }
  }

  function parkOn(radio, channel, width, band) {
    if (!radio || !channel) return
    var useBand = band || radio.band || ""
    setBandFor(radio.phy, useBand)
    pendingChannel = channel
    pendingWidth = width || 20
    if (!isPassive(radio)) {
      lab.activeScanStart(radio.phy, channel, useBand)
      return
    }
    if (isLocked(radio)) {
      requestLabUnlock(radio)
      return
    }
    if (radio.role === "station") lab.monitorOn(radio.phy, channel, pendingWidth, false, useBand)
    else lab.setChannel(radio.phy, channel, pendingWidth, useBand)
  }

  function selectBand(radio, band) {
    if (!radio || !band) return
    setBandFor(radio.phy, band)
  }

  function toggleScan(radio) {
    if (!radio || lab.busy) return
    var band = bandFor(radio)
    var channels = Model.scanChannels(radio, band)
    if (!channels.length) return
    if (isLocked(radio)) {
      requestLabUnlock(radio)
      return
    }
    if (Model.scanningBand(radio, band)) {
      lab.scanStop(radio.phy)
      return
    }
    lab.scanStart(radio.phy, band, channels)
  }

  function requestLabUnlock(radio) {
    if (!radio) return
    lab.stealPhy = radio.phy
    lab.stealKind = "unlock"
    lab.stealArmed = true
  }

  function confirmSteal() {
    var phy = lab.stealPhy
    var kind = lab.stealKind
    lab.stealArmed = false
    if (!phy) return
    if (kind === "unlock") {
      unlockPhy(phy)
      return
    }
    unlockPhy(phy)
    if (kind === "capture") lab.captureStart(phy, true)
    else lab.monitorOn(phy, pendingChannel || 6, pendingWidth || 20, true, "")
  }

  function setRadioCursor(index) {
    cursorActive = true
    focusSection = "radios"
    radioIndex = index
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    if (panelFlick) panelFlick.contentY = 0
    lab.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: lab
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { lab.refresh(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        RadioLabIcon {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: root.barIconColor
          badgeColor: root.urgent
          mode: lab.barMode
          radios: lab.radioCount
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) lab.refresh()
      else if (buttonCode === Qt.MiddleButton) lab.openCaptures()
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
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(680))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: lab.stealArmed
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var radio = root.selectedRadio()
        if (t === "i" || t === "I") lab.startHelper()
        else if (t === "r" || t === "R") lab.refresh()
        else if (t === "o" || t === "O") lab.openCaptures()
        else if (t === "m" || t === "M") { if (radio) root.toggleMonitor(radio) }
        else if (t === "d" || t === "D") { if (radio) root.toggleDisable(radio) }
        else if (t === "c" || t === "C") { if (radio) root.toggleCapture(radio) }
        else if (t === "p" || t === "P") {
          if (radio) root.toggleScan(radio)
        }
        else if (t === "w" || t === "W") {
          var target = root.selectedRadio()
          if (target) lab.restoreWifi(target.phy)
        }
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
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.headerHasCursor
            function focusHero() {
              root.cursorActive = true
              root.focusSection = "header"
            }

            PanelHero {
              id: hero
              width: parent.width
              title: "Radio Lab"
              detail: Model.heroDetail(lab.status)
              meta: root.heroPhraseText
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: root.helperReady ? 1.0 : 0.55
              iconComponent: Component {
                RadioLabIcon {
                  iconSize: Style.font.display
                  color: root.helperReady ? root.foreground : root.dim
                  badgeColor: root.urgent
                  mode: lab.barMode
                  radios: lab.radioCount
                }
              }
              trailingControl: Component {
                Button {
                  id: helperButton
                  visible: !root.helperReady
                  text: root.helperState === "missing" ? "Install" : "Start"
                  foreground: hero.foreground
                  fontFamily: hero.fontFamily
                  fontSize: Style.font.bodySmall
                  bordered: true
                  hasCursor: header.ringVisible
                  enabled: !lab.busy
                  tooltipText: root.toggleHint
                  onClicked: lab.startHelper()
                  onHovered: function(on) { if (on) header.focusHero() }
                }
              }
            }
          }

          Text {
            visible: lab.actionStatus !== "" || lab.lastError !== ""
            width: parent.width
            text: lab.actionStatus !== "" ? lab.actionStatus : lab.lastError
            color: lab.lastError !== "" && lab.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            visible: !root.helperReady
            width: parent.width
            text: root.helperState === "missing"
              ? "Install the helper once to arm monitor mode, channel parking, hopping, and pcap capture. Inventory still works without it."
              : "Start the helper to park radios on channels and capture. Polkit will ask for your password."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: radios.length ? ("RADIOS · " + radios.length) : "RADIOS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: radios.length === 0
              width: parent.width
              text: "No nl80211 radios yet. Plug in USB WNICs to monitor extra channels in parallel."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: radios
              RadioCard {
                required property var modelData
                required property int index
                width: column.width
                radio: modelData
                rowIndex: index
              }
            }
          }

          PanelSeparator { visible: airRows.length > 0 || root.listening; foreground: root.foreground }

          Column {
            visible: airRows.length > 0 || root.listening
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: airRows.length ? ("AIR · " + airRows.length) : "AIR"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: airRows.length === 0
              width: parent.width
              text: "Listening for beacons…"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            AirBandBlock {
              band: "2.4"
              rows: lab.air24
              showRule: false
            }
            AirBandBlock {
              band: "5"
              rows: lab.air5
              showRule: true
            }
            AirBandBlock {
              band: "6"
              rows: lab.air6
              showRule: true
            }
          }

          PanelSeparator { visible: captureRows.length > 0 || lab.captureCount > 0; foreground: root.foreground }

          Column {
            visible: captureRows.length > 0 || helperReady
            width: parent.width
            spacing: Style.space(8)

            Row {
              width: parent.width
              PanelSectionHeader {
                text: "CAPTURES"
                foreground: root.foreground
                fontFamily: root.fontFamily
                anchors.verticalCenter: parent.verticalCenter
              }
              Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth); height: 1 }
              Button {
                text: "Folder"
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                bordered: true
                onClicked: lab.openCaptures()
              }
            }

            Text {
              visible: captureRows.length === 0
              width: parent.width
              text: "Pcaps and scan surveys land in ~/radio-lab/captures"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Repeater {
              model: captureRows
              CaptureRow {
                required property var modelData
                required property int index
                width: column.width
                row: modelData
                rowIndex: index
              }
            }
          }
        }
      }

      ConfirmDialog {
        z: 20
        anchors.fill: parent
        opened: lab.stealArmed
        message: lab.stealKind === "unlock"
          ? "This PCIe radio is your internet link. Using it for lab work will drop Wi-Fi. Prefer the USB NIC. Restore Wi-Fi brings this radio back."
          : "This is your only station radio. Monitor mode will drop Wi-Fi internet. Plug in a USB WNIC to capture without disconnecting."
        confirmText: lab.stealKind === "unlock" ? "Use for lab" : "Convert anyway"
        cancelText: "Cancel"
        foreground: root.foreground
        background: Color.popups.background
        fontFamily: root.fontFamily
        onCanceled: lab.stealArmed = false
        onConfirmed: root.confirmSteal()
      }
    }
  }

  Timer {
    interval: 2800
    running: root.opened && root.helperReady && lab.captureCount === 0
    repeat: true
    onTriggered: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
  }

  component RadioCard: CursorSurface {
    id: card
    property var radio: ({})
    property int rowIndex: 0
    hasCursor: root.cursorActive && root.focusSection === "radios" && root.radioIndex === rowIndex
    foreground: root.foreground
    implicitHeight: inner.implicitHeight + Style.space(16)
    bordered: true

    readonly property string focusBand: root.bandFor(radio)
    readonly property var presets: Model.channelPresets(radio, focusBand)
    readonly property var scanChans: Model.scanChannels(radio, focusBand)
    readonly property bool scanning: Model.scanningBand(radio, focusBand)
    readonly property var widths: Model.widthOptions(radio, focusBand)
    readonly property var bandChoices: Model.radioBands(radio)
    readonly property bool uplink: Model.isUplink(radio)
    readonly property bool labLocked: root.isLocked(radio)

    Column {
      id: inner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Column {
          width: parent.width - rolePill.implicitWidth - parent.spacing
          spacing: Style.space(2)
          Text {
            width: parent.width
            text: Model.radioTitle(card.radio)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            text: Model.radioMeta(card.radio)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        BorderSurface {
          id: rolePill
          implicitWidth: roleText.implicitWidth + Style.space(10)
          implicitHeight: roleText.implicitHeight + Style.space(4)
          anchors.verticalCenter: parent.verticalCenter
          color: "transparent"
          borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
          radius: Style.cornerRadius
          Text {
            id: roleText
            anchors.centerIn: parent
            text: !root.isPassive(card.radio)
              ? Model.radioRoleLabel(card.radio)
              : (card.uplink && card.labLocked && !card.radio.disabled ? "Internet" : Model.radioRoleLabel(card.radio))
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }
      }

      Text {
        width: parent.width
        text: Model.radioChannelText(card.radio)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Text {
        visible: !!(card.radio.error)
        width: parent.width
        text: String(card.radio.error || "")
        color: root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Text {
        visible: !card.radio.error && !!(card.radio.note) && (card.radio.role === "hopper" || card.radio.role === "active")
        width: parent.width
        text: String(card.radio.note || "")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Flow {
        width: parent.width
        spacing: Style.space(6)

        Button {
          text: "Restore Wi-Fi"
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          foreground: root.foreground
          bordered: true
          enabled: !lab.busy
          tooltipText: "Stop lab mode on this NIC and reconnect it to Wi-Fi"
          onClicked: lab.restoreWifi(card.radio.phy)
        }
        Button {
          text: "Disable"
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          foreground: root.foreground
          bordered: true
          selected: !!card.radio.disabled
          enabled: !lab.busy && root.helperReady
          tooltipText: card.uplink
            ? "Take this NIC down (drops internet). Click again to bring it back up."
            : "Take this NIC down. Click again to bring it back up."
          onClicked: root.toggleDisable(card.radio)
        }
        Button {
          visible: card.labLocked
          text: "Use for lab"
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          foreground: root.urgent
          bordered: true
          enabled: !lab.busy
          onClicked: root.requestLabUnlock(card.radio)
        }
      }

      Text {
        visible: card.labLocked
        width: parent.width
        text: "Locked so passive monitor cannot drop your internet. Use Active scan on a channel, or the USB NIC for 6 GHz."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Flow {
        visible: card.bandChoices.length > 1 && !card.labLocked
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: card.bandChoices
          Button {
            required property var modelData
            text: modelData === "6" ? "6 GHz" : (modelData === "2.4" ? "2.4 GHz" : "5 GHz")
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            foreground: root.foreground
            bordered: true
            selected: card.focusBand === modelData
            enabled: root.helperReady && !lab.busy
            onClicked: root.selectBand(card.radio, modelData)
          }
        }
      }

      Flow {
        visible: !card.labLocked
        width: parent.width
        spacing: Style.space(6)
        opacity: root.helperReady ? 1 : 0.45

        Button {
          text: !root.isPassive(card.radio)
            ? (card.scanning ? "Stop scan" : "Scan")
            : "Monitor"
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          foreground: root.foreground
          bordered: true
          selected: !root.isPassive(card.radio)
            ? card.scanning
            : card.radio.role === "monitor"
          enabled: !lab.busy && (root.helperReady || card.radio.role !== "station" || !root.isPassive(card.radio))
          tooltipText: !root.isPassive(card.radio)
            ? (card.scanning
              ? "Stop scanning the selected band"
              : "Scan the selected band for networks. This NIC cannot passive-monitor.")
            : (card.radio.role === "monitor"
              ? "Click again to leave monitor mode"
              : "Put this NIC in monitor mode")
          onClicked: !root.isPassive(card.radio) ? root.toggleScan(card.radio) : root.toggleMonitor(card.radio)
        }

        Button {
          text: card.radio.capturing ? "Stop cap" : "Capture"
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          foreground: card.radio.capturing ? root.urgent : root.foreground
          bordered: true
          selected: !!card.radio.capturing
          enabled: root.helperReady && !lab.busy
          tooltipText: !root.isPassive(card.radio)
            ? (card.radio.capturing
              ? "Stop the active-scan survey"
              : "This NIC cannot park in monitor mode. Capture writes a jsonl survey plus a radiotap pcap of beacons rebuilt from iw scan — not a live 802.11 listen. Plug in the USB lab NIC for that.")
            : (card.radio.capturing ? "Stop writing the pcap" : "Write a live radiotap pcap of the parked channel")
          onClicked: root.toggleCapture(card.radio)
        }

        Button {
          visible: root.isPassive(card.radio) && card.scanChans.length > 0
          text: card.scanning ? "Stop scan" : "Scan"
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          foreground: root.foreground
          bordered: true
          selected: card.scanning
          enabled: root.helperReady && !lab.busy
          tooltipText: card.scanning
            ? "Stop scanning " + (card.focusBand === "6" ? "6 GHz" : (card.focusBand === "5" ? "5 GHz" : "2.4 GHz"))
            : ("Scan " + (card.focusBand === "6" ? "6 GHz" : (card.focusBand === "5" ? "5 GHz" : "2.4 GHz")) + " for networks")
          onClicked: root.toggleScan(card.radio)
        }
      }

      Flow {
        visible: !card.labLocked
        width: parent.width
        spacing: Style.space(4)
        Repeater {
          model: card.presets
          Button {
            required property var modelData
            text: modelData.label || String(modelData.channel)
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            foreground: root.foreground
            bordered: true
            selected: Number(card.radio.channel) === Number(modelData.channel) && String(card.radio.band || "") === String(modelData.band || "") && card.radio.role !== "hopper"
            horizontalPadding: Style.space(8)
            verticalPadding: Style.space(3)
            enabled: root.helperReady && !lab.busy
            onClicked: root.parkOn(card.radio, modelData.channel, Model.parkWidth(card.radio, modelData.band), modelData.band)
          }
        }
      }

      Flow {
        visible: !card.labLocked && root.isPassive(card.radio)
        width: parent.width
        spacing: Style.space(4)
        Text {
          text: "WIDTH"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          height: Style.font.caption + Style.space(8)
          verticalAlignment: Text.AlignVCenter
        }
        Repeater {
          model: card.widths
          Button {
            required property var modelData
            text: modelData + " MHz"
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            foreground: root.foreground
            bordered: true
            selected: Number(card.radio.width) === Number(modelData)
            horizontalPadding: Style.space(7)
            verticalPadding: Style.space(3)
            enabled: root.helperReady && !lab.busy && card.radio.role !== "station"
            onClicked: {
              if (card.radio.channel)
                lab.setChannel(card.radio.phy, card.radio.channel, modelData, card.radio.band || "")
            }
          }
        }
      }
    }

    HoverHandler {
      onHoveredChanged: if (hovered) root.setRadioCursor(card.rowIndex)
    }
  }

  component AirBandBlock: Column {
    property string band: ""
    property var rows: []
    property bool showRule: false
    width: column.width
    spacing: Style.space(6)

    PanelSeparator {
      visible: showRule
      width: parent.width
      foreground: root.foreground
    }

    PanelSectionHeader {
      text: Model.airBandTitle(band, rows ? rows.length : 0)
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Text {
      visible: !rows || rows.length === 0
      width: parent.width
      text: "No BSS"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Repeater {
      model: rows
      AirRow {
        required property var modelData
        required property int index
        width: column.width
        row: modelData
        rowIndex: index
      }
    }
  }

  component AirRow: Row {
    id: air
    property var row: ({})
    property int rowIndex: 0
    spacing: Style.space(8)
    height: Math.max(ssidText.implicitHeight, rssiText.implicitHeight)

    Text {
      id: chText
      width: Style.space(28)
      text: row.channel ? String(row.channel) : "—"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Text {
      id: widthText
      width: Style.space(52)
      text: Model.formatWidth(row.width)
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Text {
      id: ssidText
      width: parent.width - chText.width - widthText.width - rssiText.width - secText.width - parent.spacing * 4
      text: Model.ssidLabel(row)
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }
    Text {
      id: secText
      text: row.security || ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
    Text {
      id: rssiText
      text: Model.formatRssi(row.rssi)
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  component CaptureRow: CursorSurface {
    id: cap
    property var row: ({})
    property int rowIndex: 0
    hasCursor: root.cursorActive && root.focusSection === "captures" && root.captureIndex === rowIndex
    foreground: root.foreground
    implicitHeight: capInner.implicitHeight + Style.space(12)

    Row {
      id: capInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Column {
        width: parent.width - openBtn.implicitWidth - parent.spacing
        spacing: Style.space(2)
        Text {
          width: parent.width
          text: row.name || Model.captureName(row.path)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideMiddle
        }
        Text {
          width: parent.width
          text: Model.formatBytes(row.bytes) + " · " + Model.relativeTime(row.mtime, Date.now())
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Button {
        id: openBtn
        text: "Open"
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        foreground: root.foreground
        bordered: true
        onClicked: lab.openCapture(row.path)
      }
    }
  }
}
