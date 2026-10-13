import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "cider.bar"

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName)
    : null
  readonly property bool connected: service ? service.connected : false
  readonly property bool hasMedia: service ? service.hasMedia : false
  readonly property bool playing: service ? service.playing : false
  readonly property string title: service ? service.title : ""
  readonly property string artist: service ? service.artist : ""
  readonly property string album: service ? service.album : ""
  readonly property string artUrl: service ? service.artUrl : ""
  readonly property string playbackState: service ? service.playbackState : "Not running"
  readonly property string statusText: hasMedia
    ? title + (artist ? "  ·  " + artist : "")
    : connected ? "Cider" : "Cider offline"
  readonly property string statusIcon: !connected ? "󰝚" : playing ? "󰏤" : "󰐊"

  property bool popupOpen: false
  readonly property bool opened: popupOpen
  property real maxLabelWidth: Style.space(150)

  function open() { popupOpen = true }
  function close() { popupOpen = false }
  onPopupOpenChanged: label.scheduleScroll()
  function transport(action) {
    return service ? service.runAction(action) : false
  }
  function primaryAction() {
    return service ? service.primaryAction() : false
  }

  implicitWidth: mediaRow.implicitWidth + Style.space(10)
  implicitHeight: barSize

  Row {
    id: mediaRow
    anchors.centerIn: parent
    spacing: Style.space(4)

    Text {
      id: glyph
      anchors.verticalCenter: parent.verticalCenter
      text: root.statusIcon
      textFormat: Text.PlainText
      color: root.playing
        ? root.bar.barForeground
        : Qt.darker(root.bar.barForeground, root.connected ? 1.45 : 1.8)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
    }

    Image {
      id: barArtwork
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(16)
      height: width
      source: root.artUrl
      fillMode: Image.PreserveAspectCrop
      sourceSize.width: 32
      sourceSize.height: 32
      asynchronous: true
      visible: !root.bar.vertical && status === Image.Ready
    }

    Item {
      id: labelClip
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.bar.vertical
      width: Math.min(root.maxLabelWidth, label.implicitWidth)
      height: glyph.height
      clip: true
      onWidthChanged: label.scheduleScroll()

      Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        text: root.statusText
        textFormat: Text.PlainText
        color: root.bar.barForeground
        opacity: root.connected ? 1.0 : 0.62
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body

        property bool needsScroll: implicitWidth > labelClip.width
        property bool scrollRestartPending: false

        function scheduleScroll() {
          if (scrollRestartPending) return
          scrollRestartPending = true
          Qt.callLater(function() {
            scrollRestartPending = false
            scrollAnimation.stop()
            label.x = 0
            if (label.needsScroll && !root.popupOpen && !root.bar.vertical)
              scrollAnimation.start()
          })
        }

        onTextChanged: scheduleScroll()
        onNeedsScrollChanged: scheduleScroll()
        Component.onCompleted: scheduleScroll()

        NumberAnimation {
          id: scrollAnimation
          target: label
          property: "x"
          loops: Animation.Infinite
          duration: Math.max(6000, label.implicitWidth * 25)
          from: labelClip.width
          to: -label.implicitWidth
          easing.type: Easing.Linear
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) root.opened ? root.close() : root.open()
      else if (mouse.button === Qt.MiddleButton) root.transport("next")
      else root.primaryAction()
    }

    onWheel: function(wheel) {
      if (!root.connected) return
      if (wheel.angleDelta.y > 0) root.transport("previous")
      else if (wheel.angleDelta.y < 0) root.transport("next")
    }

    onEntered: if (root.bar) root.bar.showTooltip(root, root.statusText)
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(320))
    contentHeight: popup.fittedContentHeight(content.implicitHeight)

    Column {
      id: content
      anchors.fill: parent
      spacing: Style.space(10)

      Row {
        width: parent.width
        spacing: Style.space(10)

        BorderSurface {
          width: Style.space(72)
          height: Style.space(72)
          radius: Style.spacing.labelGap
          color: Style.normalFillFor(root.bar.foreground, Color.accent)
          borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)

          Image {
            id: artwork
            anchors.fill: parent
            anchors.margins: Style.space(2)
            source: root.artUrl
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 144
            sourceSize.height: 144
            asynchronous: true
            visible: status === Image.Ready
          }

          Text {
            anchors.centerIn: parent
            visible: artwork.status !== Image.Ready
            text: "󰝚"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
          }
        }

        Column {
          width: parent.width - Style.space(82)
          spacing: Style.space(3)

          Text {
            width: parent.width
            text: root.title || "Cider"
            textFormat: Text.PlainText
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            text: root.artist
            textFormat: Text.PlainText
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            visible: text !== ""
          }

          Text {
            width: parent.width
            text: root.album
            textFormat: Text.PlainText
            color: Qt.darker(root.bar.foreground, 1.55)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            visible: text !== ""
          }

          Text {
            width: parent.width
            text: root.playbackState
            textFormat: Text.PlainText
            color: root.playing ? Color.accent : Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(6)

        Button {
          iconText: "󰒮"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.connected && service && service.player && service.player.canGoPrevious
          opacity: enabled ? 1.0 : 0.4
          onClicked: root.transport("previous")
        }

        Button {
          iconText: !root.connected ? "󰐕" : root.playing ? "󰏤" : "󰐊"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.panelGap
          verticalPadding: Style.spacing.controlPaddingY
          iconSize: Style.font.iconLarge
          enabled: !root.connected || (service && service.player
            && (service.player.canTogglePlaying || service.player.canPlay || service.player.canPause))
          opacity: enabled ? 1.0 : 0.4
          onClicked: root.primaryAction()
        }

        Button {
          iconText: "󰒭"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.connected && service && service.player && service.player.canGoNext
          opacity: enabled ? 1.0 : 0.4
          onClicked: root.transport("next")
        }
      }

    }
  }
}
