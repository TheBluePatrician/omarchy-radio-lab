import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property color badgeColor: Color.urgent
  property string mode: "idle"   // empty | idle | monitor | capture
  property int radios: 0
  property bool showBadge: radios > 0

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  readonly property color waveColor: root.mode === "empty" ? Qt.darker(root.color, 1.7) : root.color
  readonly property real pulse: root.mode === "capture" ? pulseAnim.value : 1

  property real sweep: 0

  Canvas {
    id: canvas
    anchors.fill: parent
    opacity: root.pulse
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      var size = Math.min(width, height)
      var cx = width / 2
      var cy = height / 2 + size * 0.12
      var c = root.waveColor
      var rgb = "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + ","
      ctx.lineWidth = Math.max(1.2, size * 0.08)
      ctx.lineCap = "round"
      ctx.fillStyle = rgb + "1)"
      ctx.beginPath()
      ctx.arc(cx, cy, size * 0.07, 0, Math.PI * 2)
      ctx.fill()
      for (var i = 1; i <= 3; i++) {
        ctx.beginPath()
        ctx.strokeStyle = rgb + (i === 3 ? "0.45)" : "0.95)")
        ctx.arc(cx, cy, size * (0.14 + i * 0.16), Math.PI * 1.18, Math.PI * 1.82)
        ctx.stroke()
      }
    }
    Connections {
      target: root
      function onColorChanged() { canvas.requestPaint() }
      function onModeChanged() { canvas.requestPaint() }
      function onWaveColorChanged() { canvas.requestPaint() }
    }
  }

  Rectangle {
    visible: root.mode === "empty"
    anchors.centerIn: parent
    width: parent.width * 1.18
    height: Math.max(1.6, parent.height * 0.12)
    radius: height / 2
    color: root.color
    rotation: -45
  }

  BorderSurface {
    visible: root.showBadge
    width: Math.max(8, parent.width * 0.48)
    height: width
    radius: width / 2
    color: root.mode === "capture" ? root.badgeColor : Color.popups.background
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: -1
    anchors.bottomMargin: -1
    borderSpec: Border.flat(root.mode === "capture" ? root.badgeColor : root.color, 1)

    Text {
      anchors.centerIn: parent
      text: root.radios > 9 ? "9+" : String(Math.max(0, root.radios))
      color: root.mode === "capture" ? Color.background : root.color
      font.family: Style.font.family
      font.pixelSize: Math.max(6, parent.height * 0.62)
      font.bold: true
    }
  }

  SequentialAnimation on sweep {
    running: root.mode === "monitor" || root.mode === "capture"
    loops: Animation.Infinite
    NumberAnimation { from: 0; to: 1; duration: 1600; easing.type: Easing.InOutSine }
  }

  QtObject {
    id: pulseAnim
    property real value: 1
  }

  SequentialAnimation {
    running: root.mode === "capture"
    loops: Animation.Infinite
    NumberAnimation { target: pulseAnim; property: "value"; from: 1; to: 0.55; duration: 700; easing.type: Easing.InOutSine }
    NumberAnimation { target: pulseAnim; property: "value"; from: 0.55; to: 1; duration: 700; easing.type: Easing.InOutSine }
  }

  onSweepChanged: canvas.requestPaint()
}
