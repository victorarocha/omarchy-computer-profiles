import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "lutfi.glass"
  ipcTarget: "lutfi.glass"
  manageIpc: true

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  readonly property string helperPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/lutfi.glass/bin/glass-ctl"

  property real activeOpacity: 0.88
  property real inactiveOpacity: 0.78
  property bool blurEnabled: true
  property int blurPasses: 3
  property int blurSize: 6
  property bool barBlurEnabled: true
  property string barColorMode: "theme"
  property string barCustomColor: "#5eead4"
  property real barGlassOpacity: 0.60
  property real pickerHue: 0.47
  property real pickerSat: 0.60
  property real pickerVal: 0.92
  property bool loaded: false

  function syncPickerFromHex(hexStr) {
    var hex = String(hexStr || "").trim().replace(/^#/, "")
    if (hex.length === 3) hex = hex.split("").map(function(x) { return x + x }).join("")
    if (hex.length !== 6) return
    var r = parseInt(hex.substring(0, 2), 16) / 255
    var g = parseInt(hex.substring(2, 4), 16) / 255
    var b = parseInt(hex.substring(4, 6), 16) / 255
    var max = Math.max(r, g, b), min = Math.min(r, g, b)
    var delta = max - min
    var h = 0, s = 0, v = max
    if (max > 0) s = delta / max
    if (delta > 0) {
      if (max === r) h = (g - b) / delta + (g < b ? 6 : 0)
      else if (max === g) h = (b - r) / delta + 2
      else h = (r - g) / delta + 4
      h /= 6
    }
    pickerHue = Math.max(0, Math.min(1, h))
    pickerSat = Math.max(0, Math.min(1, s))
    pickerVal = Math.max(0, Math.min(1, v))
  }

  function currentPickedHex() {
    var h = pickerHue, s = pickerSat, v = pickerVal
    var r = 0, g = 0, b = 0
    var i = Math.floor(h * 6)
    var f = h * 6 - i
    var p = v * (1 - s)
    var q = v * (1 - f * s)
    var t = v * (1 - (1 - f) * s)
    switch (i % 6) {
      case 0: r = v; g = t; b = p; break
      case 1: r = q; g = v; b = p; break
      case 2: r = p; g = v; b = t; break
      case 3: r = p; g = q; b = v; break
      case 4: r = t; g = p; b = v; break
      case 5: r = v; g = p; b = q; break
    }
    function toHex(x) {
      var hex = Math.round(Math.max(0, Math.min(1, x)) * 255).toString(16)
      return hex.length < 2 ? "0" + hex : hex
    }
    return "#" + toHex(r) + toHex(g) + toHex(b)
  }

  function applyPickedColor(liveOnly) {
    var hex = currentPickedHex()
    barCustomColor = hex
    barColorMode = "custom"
    applySettings(liveOnly)
  }

  function loadSettings() {
    getProc.running = true
  }

  function parseSettings(text) {
    try {
      var data = JSON.parse(text)
      if (data.activeOpacity !== undefined) root.activeOpacity = data.activeOpacity
      if (data.inactiveOpacity !== undefined) root.inactiveOpacity = data.inactiveOpacity
      if (data.blurEnabled !== undefined) root.blurEnabled = data.blurEnabled
      if (data.blurPasses !== undefined) root.blurPasses = data.blurPasses
      if (data.blurSize !== undefined) root.blurSize = data.blurSize
      if (data.barBlur !== undefined) root.barBlurEnabled = data.barBlur === true
      if (data.barColorMode !== undefined) root.barColorMode = String(data.barColorMode || "theme")
      if (data.barColor !== undefined) {
        root.barCustomColor = String(data.barColor || "").trim()
        if (root.barCustomColor.length > 0) root.syncPickerFromHex(root.barCustomColor)
      }
      if (data.barGlassOpacity !== undefined) {
        var op = parseFloat(data.barGlassOpacity)
        if (!isNaN(op) && op >= 0 && op <= 1) root.barGlassOpacity = op
      }
      root.loaded = true
    } catch (e) {}
  }

  function applySettings(liveOnly) {
    if (!loaded) return
    var action = liveOnly ? "live" : "set"
    var args = [
      helperPath,
      action,
      activeOpacity.toFixed(2),
      inactiveOpacity.toFixed(2),
      blurEnabled ? "true" : "false",
      String(blurPasses),
      String(blurSize),
      barBlurEnabled ? "true" : "false",
      barColorMode,
      barCustomColor || "",
      barGlassOpacity.toFixed(2)
    ]
    Quickshell.execDetached(args)
  }

  function applyPreset(active, inactive, blur, passes, size) {
    activeOpacity = active
    inactiveOpacity = inactive
    blurEnabled = blur
    blurPasses = passes
    blurSize = size
    applySettings(false)
  }

  Process {
    id: getProc
    command: [root.helperPath, "get"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseSettings(text)
    }
  }

  Component.onCompleted: loadSettings()
  onOpenedChanged: if (opened) loadSettings()

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰾆"
    tooltipText: "Glass & Blur Control"
    onPressed: function(b) {
      if (b === Qt.LeftButton || b === Qt.MiddleButton) root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: hexField.activeFocus
      onCloseRequested: root.close()

      Column {
        id: mainColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // Header row with Icon, Title, and Blur Toggle
        RowLayout {
          width: parent.width
          spacing: Style.space(8)

          Text {
            text: "󰾆"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
              text: "Glass & Blur"
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Text {
              text: root.blurEnabled ? "Frosted glass enabled" : "Blur disabled (transparency only)"
              color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          ToggleSwitch {
            checked: root.blurEnabled
            onToggled: {
              root.blurEnabled = !root.blurEnabled
              root.applySettings(false)
            }
          }
        }

        PanelSeparator {
          foreground: root.bar ? root.bar.foreground : Color.foreground
        }

        // Section 1: Active Opacity
        Column {
          width: parent.width
          spacing: Style.space(6)

          RowLayout {
            width: parent.width

            PanelSectionHeader {
              text: "ACTIVE WINDOW OPACITY"
              foreground: root.bar ? root.bar.foreground : Color.foreground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            }

            Item { Layout.fillWidth: true }

            Text {
              text: Math.round((opacitySlider.dragging ? opacitySlider.liveValue : root.activeOpacity) * 100) + "%"
              color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          PanelSlider {
            id: opacitySlider
            bar: root.bar
            width: parent.width
            minimum: 0.50
            maximum: 1.00
            step: 0.01
            value: root.activeOpacity
            onMoved: function(v) {
              root.activeOpacity = v
              root.inactiveOpacity = Math.max(0.40, Math.round((v - 0.10) * 100) / 100)
              root.applySettings(true)
            }
            onReleased: function(v) {
              root.activeOpacity = v
              root.inactiveOpacity = Math.max(0.40, Math.round((v - 0.10) * 100) / 100)
              root.applySettings(false)
            }
          }
        }

        // Section 2: Blur Passes
        Column {
          width: parent.width
          spacing: Style.space(6)
          opacity: root.blurEnabled ? 1.0 : 0.4

          RowLayout {
            width: parent.width

            PanelSectionHeader {
              text: "BLUR PASSES (SMOOTHNESS)"
              foreground: root.bar ? root.bar.foreground : Color.foreground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            }

            Item { Layout.fillWidth: true }

            Text {
              readonly property int pVal: Math.round(passesSlider.dragging ? passesSlider.liveValue : root.blurPasses)
              text: pVal + (pVal <= 1 ? " (Low)" : pVal <= 2 ? " (Med)" : pVal <= 3 ? " (High)" : " (Ultra)")
              color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          PanelSlider {
            id: passesSlider
            bar: root.bar
            width: parent.width
            minimum: 1
            maximum: 5
            step: 1
            integer: true
            value: root.blurPasses
            onMoved: function(v) {
              root.blurPasses = Math.round(v)
              root.applySettings(true)
            }
            onReleased: function(v) {
              root.blurPasses = Math.round(v)
              root.applySettings(false)
            }
          }
        }

        // Section 3: Blur Radius (Size)
        Column {
          width: parent.width
          spacing: Style.space(6)
          opacity: root.blurEnabled ? 1.0 : 0.4

          RowLayout {
            width: parent.width

            PanelSectionHeader {
              text: "BLUR RADIUS (SIZE)"
              foreground: root.bar ? root.bar.foreground : Color.foreground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            }

            Item { Layout.fillWidth: true }

            Text {
              text: Math.round(sizeSlider.dragging ? sizeSlider.liveValue : root.blurSize) + "px"
              color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          PanelSlider {
            id: sizeSlider
            bar: root.bar
            width: parent.width
            minimum: 2
            maximum: 12
            step: 1
            integer: true
            value: root.blurSize
            onMoved: function(v) {
              root.blurSize = Math.round(v)
              root.applySettings(true)
            }
            onReleased: function(v) {
              root.blurSize = Math.round(v)
              root.applySettings(false)
            }
          }
        }

        PanelSeparator {
          foreground: root.bar ? root.bar.foreground : Color.foreground
        }

        // Section 4: Top Bar Blur & Tint
        Column {
          width: parent.width
          spacing: Style.space(6)

          Toggle {
            width: parent.width
            label: "Top Bar Blur"
            description: root.barBlurEnabled ? "Frosted glass blur active on status bar" : "Status bar blur disabled"
            checked: root.barBlurEnabled
            foreground: root.bar ? root.bar.foreground : Color.foreground
            accent: root.bar ? root.bar.urgent : Color.accent
            onClicked: {
              root.barBlurEnabled = !root.barBlurEnabled
              root.applySettings(false)
            }
          }

          // Glass Tint Opacity Slider (visible when blur is enabled)
          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: root.barBlurEnabled

            RowLayout {
              width: parent.width

              Text {
                text: "BAR TINT OPACITY"
                color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.3)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Item { Layout.fillWidth: true }

              Text {
                text: Math.round(barTintSlider.dragging ? barTintSlider.liveValue * 100 : root.barGlassOpacity * 100) + "%"
                color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            PanelSlider {
              id: barTintSlider
              bar: root.bar
              width: parent.width
              minimum: 0.30
              maximum: 0.95
              step: 0.01
              value: root.barGlassOpacity
              onMoved: function(v) {
                root.barGlassOpacity = v
                root.applySettings(true)
              }
              onReleased: function(v) {
                root.barGlassOpacity = v
                root.applySettings(false)
              }
            }
          }
        }

        PanelSeparator {
          foreground: root.bar ? root.bar.foreground : Color.foreground
        }

        // Section 5: Bar Color Mode
        Column {
          width: parent.width
          spacing: Style.space(8)

          RowLayout {
            width: parent.width

            PanelSectionHeader {
              text: "BAR COLOR MODE"
              foreground: root.bar ? root.bar.foreground : Color.foreground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            }

            Item { Layout.fillWidth: true }

            Text {
              text: root.barColorMode === "theme" ? "Adaptive"
                  : (root.barColorMode === "theme-accent" || root.barColorMode === "theme-direct") ? "Theme Accent"
                  : root.barColorMode === "invert" ? "Inverted"
                  : "Custom"
              color: root.bar ? root.bar.urgent : Color.accent
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          // Mode buttons grid (2x2)
          GridLayout {
            width: parent.width
            columns: 2
            rowSpacing: Style.space(6)
            columnSpacing: Style.space(6)

            Button {
              Layout.fillWidth: true
              text: "Theme Auto"
              bordered: true
              active: root.barColorMode === "theme"
              onClicked: {
                root.barColorMode = "theme"
                root.applySettings(false)
              }
            }

            Button {
              Layout.fillWidth: true
              text: "Theme Accent"
              bordered: true
              active: root.barColorMode === "theme-accent" || root.barColorMode === "theme-direct"
              onClicked: {
                root.barColorMode = "theme-accent"
                root.applySettings(false)
              }
            }

            Button {
              Layout.fillWidth: true
              text: "Invert Palette"
              bordered: true
              active: root.barColorMode === "invert"
              onClicked: {
                root.barColorMode = "invert"
                root.applySettings(false)
              }
            }

            Button {
              Layout.fillWidth: true
              text: "Custom Picker"
              bordered: true
              active: root.barColorMode === "custom"
              onClicked: {
                root.barColorMode = "custom"
                root.applySettings(false)
              }
            }
          }

          // Visual Canva / Adobe Color Picker (visible when custom mode is selected)
          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: root.barColorMode === "custom"

            // 2D Saturation / Value (SV) Canvas Box
            Rectangle {
              id: svBox
              width: parent.width
              height: Style.space(115)
              radius: Style.cornerRadius > 0 ? Style.space(6) : 0
              clip: true
              color: Qt.hsva(root.pickerHue, 1.0, 1.0, 1.0)
              border.width: 1
              border.color: Qt.rgba(1, 1, 1, 0.15)

              // Horizontal gradient (Saturation: White to Transparent)
              Rectangle {
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                  orientation: Gradient.Horizontal
                  GradientStop { position: 0.0; color: "#ffffff" }
                  GradientStop { position: 1.0; color: "#00ffffff" }
                }
              }

              // Vertical gradient (Brightness: Transparent to Black)
              Rectangle {
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                  orientation: Gradient.Vertical
                  GradientStop { position: 0.0; color: "#00000000" }
                  GradientStop { position: 1.0; color: "#ff000000" }
                }
              }

              // Draggable circular handle
              Rectangle {
                x: Math.max(0, Math.min(svBox.width - width, root.pickerSat * svBox.width - width / 2))
                y: Math.max(0, Math.min(svBox.height - height, (1.0 - root.pickerVal) * svBox.height - height / 2))
                width: Style.space(14)
                height: Style.space(14)
                radius: width / 2
                color: Qt.hsva(root.pickerHue, root.pickerSat, root.pickerVal, 1.0)
                border.width: 2
                border.color: "#ffffff"
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.CrossCursor
                function updateSV(mouse) {
                  root.pickerSat = Math.max(0, Math.min(1, mouse.x / svBox.width))
                  root.pickerVal = Math.max(0, Math.min(1, 1.0 - (mouse.y / svBox.height)))
                  root.applyPickedColor(false)
                }
                onPressed: function(mouse) { updateSV(mouse) }
                onPositionChanged: function(mouse) { if (pressed) updateSV(mouse) }
              }
            }

            // 1D Rainbow Hue Slider
            Rectangle {
              id: hueSlider
              width: parent.width
              height: Style.space(14)
              radius: height / 2
              clip: true
              gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.000; color: "#ff0000" }
                GradientStop { position: 0.166; color: "#ffff00" }
                GradientStop { position: 0.333; color: "#00ff00" }
                GradientStop { position: 0.500; color: "#00ffff" }
                GradientStop { position: 0.666; color: "#0000ff" }
                GradientStop { position: 0.833; color: "#ff00ff" }
                GradientStop { position: 1.000; color: "#ff0000" }
              }

              // Hue thumb indicator
              Rectangle {
                x: Math.max(0, Math.min(hueSlider.width - width, root.pickerHue * hueSlider.width - width / 2))
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(18)
                height: Style.space(18)
                radius: width / 2
                color: Qt.hsva(root.pickerHue, 1.0, 1.0, 1.0)
                border.width: 2
                border.color: "#ffffff"
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                function updateHue(mouse) {
                  root.pickerHue = Math.max(0, Math.min(1, mouse.x / hueSlider.width))
                  root.applyPickedColor(false)
                }
                onPressed: function(mouse) { updateHue(mouse) }
                onPositionChanged: function(mouse) { if (pressed) updateHue(mouse) }
              }
            }

            // Quick color swatches row
            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: [
                  { name: "White", color: "#ffffff" },
                  { name: "Black", color: "#111111" },
                  { name: "Cyan", color: "#5eead4" },
                  { name: "Lavender", color: "#c084fc" },
                  { name: "Rose", color: "#fb7185" },
                  { name: "Amber", color: "#fbbf24" },
                  { name: "Emerald", color: "#34d399" },
                  { name: "Coral", color: "#fb923c" }
                ]

                Rectangle {
                  id: swatchItem
                  required property var modelData
                  Layout.fillWidth: true
                  height: Style.space(22)
                  radius: Style.cornerRadius > 0 ? Style.space(4) : 0
                  color: modelData.color
                  border.width: (root.barCustomColor.toLowerCase() === modelData.color.toLowerCase()) ? 2 : 1
                  border.color: (root.barCustomColor.toLowerCase() === modelData.color.toLowerCase())
                    ? "#ffffff"
                    : Qt.rgba(1, 1, 1, 0.25)

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.barCustomColor = swatchItem.modelData.color
                      root.syncPickerFromHex(swatchItem.modelData.color)
                      root.barColorMode = "custom"
                      root.applySettings(false)
                    }
                  }
                }
              }
            }

            // Live Color Swatch & Hex input row
            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              Rectangle {
                width: Style.space(28)
                height: Style.space(28)
                radius: Style.cornerRadius > 0 ? Style.space(4) : 0
                color: root.barCustomColor ? Qt.color(root.barCustomColor) : Qt.hsva(root.pickerHue, root.pickerSat, root.pickerVal, 1.0)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.3)
              }

              TextField {
                id: hexField
                Layout.fillWidth: true
                height: Style.space(28)
                placeholderText: "Hex code (e.g. #5eead4)"
                text: root.barCustomColor
                font.pixelSize: Style.font.caption
                onAccepted: {
                  var val = text.trim()
                  if (val.length > 0 && val.charAt(0) !== "#") val = "#" + val
                  root.barCustomColor = val
                  root.syncPickerFromHex(val)
                  root.barColorMode = "custom"
                  root.applySettings(false)
                }
              }

              Button {
                text: "Apply"
                height: Style.space(28)
                bordered: true
                onClicked: {
                  var val = hexField.text.trim()
                  if (val.length > 0 && val.charAt(0) !== "#") val = "#" + val
                  root.barCustomColor = val
                  root.syncPickerFromHex(val)
                  root.barColorMode = "custom"
                  root.applySettings(false)
                }
              }
            }
          }
        }

        PanelSeparator {
          foreground: root.bar ? root.bar.foreground : Color.foreground
        }

        // Section 7: Quick Presets
        Column {
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "QUICK PRESETS"
            foreground: root.bar ? root.bar.foreground : Color.foreground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          }

          GridLayout {
            width: parent.width
            columns: 2
            rowSpacing: Style.space(6)
            columnSpacing: Style.space(6)

            Button {
              Layout.fillWidth: true
              text: "Solid (100%)"
              bordered: true
              onClicked: root.applyPreset(1.00, 1.00, false, 1, 6)
            }

            Button {
              Layout.fillWidth: true
              text: "Subtle (92%)"
              bordered: true
              onClicked: root.applyPreset(0.92, 0.82, true, 2, 5)
            }

            Button {
              Layout.fillWidth: true
              text: "Frosted (88%)"
              bordered: true
              onClicked: root.applyPreset(0.88, 0.78, true, 3, 6)
            }

            Button {
              Layout.fillWidth: true
              text: "Deep (78%)"
              bordered: true
              onClicked: root.applyPreset(0.78, 0.68, true, 4, 8)
            }
          }
        }
      }
    }
  }
}
