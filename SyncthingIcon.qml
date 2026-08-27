import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property color badgeColor: Color.urgent
  property bool crossed: false
  property bool warning: false
  property bool spinning: false

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  readonly property real stroke: Math.max(1, iconSize * 0.08)
  readonly property real nodeRadius: Math.max(1, iconSize * 0.115)
  readonly property real centerRadius: Math.max(1, iconSize * 0.09)
  readonly property real lineThickness: Math.max(1, iconSize * 0.055)
  readonly property real orbit: iconSize / 2 - stroke - nodeRadius
  readonly property real cx: iconSize / 2
  readonly property real cy: iconSize / 2

  // Native rendering of the Syncthing mark: a ring, a centre node, and three
  // outer nodes joined to the centre by straight lines. Drawn from primitives
  // (like the tailscale mark) to avoid SVG rendering quirks in tiny bar slots.
  component Spoke: Rectangle {
    property real angle: 0
    x: root.cx
    y: root.cy - root.lineThickness / 2
    width: root.orbit
    height: root.lineThickness
    radius: height / 2
    color: root.color
    transformOrigin: Item.Left
    rotation: -angle
  }

  component Node: Rectangle {
    property real angle: 0
    x: root.cx + root.orbit * Math.cos(angle * Math.PI / 180) - root.nodeRadius
    y: root.cy - root.orbit * Math.sin(angle * Math.PI / 180) - root.nodeRadius
    width: root.nodeRadius * 2
    height: root.nodeRadius * 2
    radius: root.nodeRadius
    color: root.color
  }

  Item {
    id: logo
    anchors.fill: parent

    Rectangle {
      x: root.stroke / 2
      y: root.stroke / 2
      width: root.iconSize - root.stroke
      height: root.iconSize - root.stroke
      radius: width / 2
      color: "transparent"
      border.width: root.stroke
      border.color: root.color
    }

    Spoke { angle: 90 }
    Spoke { angle: 210 }
    Spoke { angle: 330 }

    Rectangle {
      x: root.cx - root.centerRadius
      y: root.cy - root.centerRadius
      width: root.centerRadius * 2
      height: root.centerRadius * 2
      radius: root.centerRadius
      color: root.color
    }

    Node { angle: 90 }
    Node { angle: 210 }
    Node { angle: 330 }

    NumberAnimation on rotation {
      running: root.spinning
      from: 0
      to: 360
      duration: 3600
      loops: Animation.Infinite
    }
  }

  Rectangle {
    visible: root.crossed
    anchors.centerIn: parent
    width: parent.width * 1.22
    height: Math.max(2, parent.height * 0.14)
    radius: height / 2
    color: root.color
    rotation: -45
  }

  BorderSurface {
    visible: root.warning
    width: Math.max(7, parent.width * 0.42)
    height: width
    radius: width / 2
    color: root.badgeColor
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    borderSpec: Border.flat(Color.popups.background, 1)

    Text {
      anchors.centerIn: parent
      text: "!"
      color: Color.background
      font.family: Style.font.family
      font.pixelSize: Math.max(6, parent.height * 0.72)
      font.bold: true
    }
  }
}
