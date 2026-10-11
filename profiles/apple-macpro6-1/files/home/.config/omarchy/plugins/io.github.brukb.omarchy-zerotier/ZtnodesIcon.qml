import QtQuick
import qs.Commons
import qs.Ui

// Native ZeroTier T+O mark traced from homarr dashboard-icons SVG (viewBox 90×90).
// Pure Rectangle geometry like TailscaleIcon — no Image/SVG loader.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property real glyphOpacity: 1.0
  property color badgeColor: Color.urgent
  property bool warning: false

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize
  opacity: glyphOpacity

  readonly property real u: iconSize / 90
  readonly property real stroke: Math.max(1, 3 * u)

  // O ring
  Rectangle {
    x: 22 * root.u
    y: 22.5 * root.u
    width: 46 * root.u
    height: 46 * root.u
    radius: 23 * root.u
    color: "transparent"
    border.color: root.color
    border.width: root.stroke
  }

  // T stem (through ring)
  Rectangle {
    x: 43.5 * root.u
    y: 14 * root.u
    width: root.stroke
    height: 67 * root.u
    color: root.color
  }

  // T crossbar
  Rectangle {
    x: 10 * root.u
    y: 11 * root.u
    width: 70 * root.u
    height: root.stroke
    color: root.color
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
      textFormat: Text.PlainText
    }
  }
}
