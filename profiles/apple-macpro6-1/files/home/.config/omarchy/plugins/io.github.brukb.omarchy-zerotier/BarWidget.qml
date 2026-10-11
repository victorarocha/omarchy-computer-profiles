import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.brukb.omarchy-zerotier"

  readonly property string apiScript: {
    var path = String(Qt.resolvedUrl("bin/ztn-api") || "")
    if (path.indexOf("file://") === 0) path = path.substring(7)
    return decodeURIComponent(path)
  }

  readonly property int refreshIntervalSec:
    Math.max(5, parseInt(String(setting("refreshIntervalSec", 15)), 10) || 15)

  property var nodeStatus: null
  property var networks: []
  property var peers: []
  property var controllerStatus: null
  property var controllerNetworks: []
  property var controllerMembers: []
  property var authInfo: ({ hasToken: false, source: "", serviceReachable: false })
  property string errorText: ""
  property bool needsAuth: false
  property bool tokenRejected: false
  property bool everLoaded: false
  property bool fetching: false
  property string busyAction: ""
  property string actionStatus: ""

  readonly property int joinedCount: networks.length
  readonly property int okCount: {
    var n = 0
    for (var i = 0; i < networks.length; i++)
      if (String(networks[i].status || "").toUpperCase() === "OK") n++
    return n
  }
  readonly property bool controllerActive:
    controllerStatus && controllerStatus.controller === true
  readonly property bool serviceOnline:
    nodeStatus && (nodeStatus.online === true || nodeStatus.online === 1)
  readonly property bool showAsOnline: serviceOnline || okCount > 0 || joinedCount > 0
  readonly property bool snapshotFetching: apiProcess.running
  readonly property bool controllerNetworksBusy:
    mutationProcess.running && mutationProcess.kind === "controllerNetworks"
  readonly property bool controllerMembersBusy:
    mutationProcess.running && mutationProcess.kind === "controllerMembers"
  readonly property bool alerting:
    everLoaded && (errorText !== "" || needsAuth || tokenRejected || !authInfo.serviceReachable)
  readonly property color barForeground: bar ? bar.barForeground : Color.foreground
  readonly property color barIconColor:
    everLoaded && showAsOnline ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property real barIconOpacity:
    everLoaded && showAsOnline ? 1.0 : 0.6
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string nodeAddress:
    nodeStatus ? Model.plain(nodeStatus.address) : ""
  readonly property string displayLabel:
    nodeAddress !== "" ? Model.shortNodeId(nodeAddress) : "ZeroTier"

  readonly property bool opened:
    panelLoader.item ? panelLoader.item.opened === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.settings = root.settings
  }

  function applyEnvelope(text, kind) {
    var env = Model.parseEnvelope(text)
    if (!env.ok) {
      root.everLoaded = true
      root.errorText = Model.plain(env.error || "request failed")
      if (kind === "controller") root.controllerStatus = null
      if (env.needsAuth === true && root.authInfo.hasToken) {
        root.tokenRejected = true
        root.needsAuth = false
      } else if (env.needsAuth === true) {
        root.needsAuth = true
        root.tokenRejected = false
      }
      return false
    }
    root.errorText = ""
    root.needsAuth = false
    root.tokenRejected = false
    root.everLoaded = true
    var data = env.body
    if (kind === "auth") {
      root.authInfo = data || root.authInfo
      return true
    }
    if (kind === "status") root.nodeStatus = data
    if (kind === "networks") root.networks = Model.normalizeNetworks(data)
    if (kind === "peers") root.peers = Model.normalizePeers(data)
    if (kind === "controller") root.controllerStatus = data
    if (kind === "controllerNetworks") root.controllerNetworks = Model.normalizeControllerNetworks(data)
    if (kind === "controllerMembers") root.controllerMembers = Model.normalizeControllerMembers(data)
    if (kind === "controllerNetwork" && data) {
      var cn = Model.normalizeControllerNetwork(data)
      if (cn) {
        var cnext = controllerNetworks.slice()
        var cfound = false
        for (var ci = 0; ci < cnext.length; ci++) {
          if (cnext[ci].id === cn.id) {
            cnext[ci] = cn
            cfound = true
            break
          }
        }
        if (!cfound) cnext.push(cn)
        root.controllerNetworks = Model.sortNetworks(cnext)
      }
    }
    if (kind === "controllerMember" && data) {
      var cm = Model.normalizeControllerMember(data)
      if (cm) {
        var mnext = controllerMembers.slice()
        var mfound = false
        for (var mj = 0; mj < mnext.length; mj++) {
          if (mnext[mj].address === cm.address) {
            mnext[mj] = cm
            mfound = true
            break
          }
        }
        if (!mfound) mnext.push(cm)
        root.controllerMembers = Model.normalizeControllerMembers(mnext)
      }
    }
    if (kind === "controllerNetworkDelete") {
      var delId = pendingControllerNetworkDeleteId
      pendingControllerNetworkDeleteId = ""
      if (delId) {
        var kept = []
        for (var cdi = 0; cdi < controllerNetworks.length; cdi++) {
          if (controllerNetworks[cdi].id !== delId) kept.push(controllerNetworks[cdi])
        }
        root.controllerNetworks = Model.sortNetworks(kept)
      }
    }
    if (kind === "controllerMemberDelete" && data === null) {
      // member list refresh follows
    }
    if (kind === "network") {
      if (data && data.id) {
        var next = networks.slice()
        var found = false
        for (var i = 0; i < next.length; i++) {
          if (next[i].id === data.id) {
            next[i] = Model.normalizeNetwork(data)
            found = true
            break
          }
        }
        if (!found) next.push(Model.normalizeNetwork(data))
        root.networks = Model.sortNetworks(next)
      }
    }
    if (kind === "leave") {
      // leave response has null data; list refresh follows
    }
    return true
  }

  function syncFetching() {
    fetching = apiProcess.running || mutationProcess.running || jsonStdinProcess.running
  }

  function finishJsonStdin(text) {
    var kind = jsonStdinProcess.kind
    var done = jsonStdinProcess.done
    var action = busyAction
    jsonStdinProcess.done = null
    var ok = applyEnvelope(text, kind)
    busyAction = ""
    if (action === "controllerCreate" && ok) {
      actionStatus = "Network created"
      refreshControllerNetworks()
    } else if (action === "controllerUpdate" && ok) {
      actionStatus = "Network updated"
    } else if (action === "memberUpdate" && ok) {
      actionStatus = "Member updated"
    } else if (action !== "" && !ok) {
      actionStatus = errorText
    }
    if (done) done(ok)
  }

  function finishMutation(text) {
    var kind = mutationProcess.kind
    var done = mutationProcess.done
    var action = busyAction
    mutationProcess.done = null
    var ok = applyEnvelope(text, kind)
    busyAction = ""
    if (kind === "leave" && ok) {
      actionStatus = "Left network"
      runMutation(["networks"], "networks")
    } else if (action === "join" && ok) {
      actionStatus = "Joined network"
      runMutation(["networks"], "networks")
    } else if (action === "set" && ok) {
      actionStatus = "Updated"
    } else if (kind === "controllerNetworks" && ok) {
      actionStatus = controllerNetworks.length + " controller network(s)"
    } else if (kind === "controllerMembers" && ok) {
      actionStatus = controllerMembers.length + " member(s)"
    } else if (action === "controllerCreate" && ok) {
      actionStatus = "Network created"
      refreshControllerNetworks()
    } else if (action === "controllerUpdate" && ok) {
      actionStatus = "Network updated"
    } else if (action === "controllerDelete" && ok) {
      actionStatus = "Network deleted"
      refreshControllerNetworks()
    } else if (action === "memberUpdate" && ok) {
      actionStatus = "Member updated"
    } else if (action === "memberDelete" && ok) {
      actionStatus = "Member removed"
      if (pendingMemberDeleteNwid)
        refreshControllerMembers(pendingMemberDeleteNwid)
      pendingMemberDeleteNwid = ""
    } else if (action !== "" && !ok) {
      actionStatus = errorText
    }
    if (done) done(ok)
  }

  function applySnapshot(text) {
    var v = Model.snapshotState(text)
    if (!v.ok) {
      everLoaded = true
      errorText = Model.plain(v.error || "request failed")
      if (v.needsAuth === true && authInfo.hasToken) {
        tokenRejected = true
        needsAuth = false
      } else if (v.needsAuth === true) {
        needsAuth = true
        tokenRejected = false
      }
      return
    }
    authInfo = {
      hasToken: v.hasToken === true,
      source: String(v.tokenSource || ""),
      serviceReachable: v.serviceReachable === true
    }
    nodeStatus = (v.address || v.online) ? {
      address: String(v.address || ""),
      online: v.online === true,
      version: String(v.version || "")
    } : null
    networks = v.networks || []
    controllerStatus = {
      controller: v.controller === true,
      apiVersion: v.apiVersion
    }
    peers = v.peers || []
    errorText = ""
    needsAuth = v.hasToken !== true
    tokenRejected = false
    everLoaded = true
    if (busyAction === "") actionStatus = ""
    if (v.controller === true) Qt.callLater(function() {
      if (apiProcess.running || mutationProcess.running || jsonStdinProcess.running) return
      if (busyAction !== "") return
      refreshControllerNetworks()
    })
  }

  function finishRefresh(text) {
    applySnapshot(text)
  }

  function runMutation(args, kind, onDone) {
    if (mutationProcess.running || jsonStdinProcess.running) return false
    mutationProcess.kind = kind
    mutationProcess.done = onDone || null
    mutationProcess.command = ["/bin/bash", root.apiScript].concat(args)
    mutationProcess.running = true
    return true
  }

  function runApi(args, kind, onDone) {
    return runMutation(args, kind, onDone)
  }

  property string pendingMemberDeleteNwid: ""
  property string pendingControllerNetworkDeleteId: ""

  function refreshAll() {
    if (apiProcess.running || mutationProcess.running || jsonStdinProcess.running) return
    if (busyAction !== "") return
    apiProcess.command = ["/bin/bash", root.apiScript, "snapshot"]
    apiProcess.running = true
  }

  function storeToken(token) {
    if (storeProcess.running) return false
    storeProcess.secret = String(token || "").replace(/\s/g, "")
    storeProcess.running = true
    return true
  }

  function clearToken() {
    runMutation(["auth", "clear"], "auth")
  }

  function joinNetwork(nwid) {
    if (busyAction !== "") return false
    busyAction = "join"
    actionStatus = "Joining…"
    return runMutation(["network", "join", nwid], "network")
  }

  function leaveNetwork(nwid, onDone) {
    if (busyAction !== "") return false
    busyAction = "leave"
    actionStatus = "Leaving…"
    return runMutation(["network", "leave", nwid], "leave", onDone)
  }

  function setNetworkFlag(nwid, key, value) {
    if (busyAction !== "") return false
    busyAction = "set"
    actionStatus = "Updating…"
    return runMutation(["network", "set", nwid, key, value ? "true" : "false"], "network")
  }

  function findNetwork(id) {
    for (var i = 0; i < networks.length; i++)
      if (networks[i].id === id) return networks[i]
    return null
  }

  function refreshControllerNetworks() {
    if (!controllerActive) return false
    if (busyAction !== "") return false
    return runMutation(["controller", "networks"], "controllerNetworks")
  }

  function runApiJsonStdin(args, jsonObj, kind, onDone) {
    if (jsonStdinProcess.running || mutationProcess.running) return false
    jsonStdinProcess.kind = kind
    jsonStdinProcess.done = onDone || null
    jsonStdinProcess.command = ["/bin/bash", root.apiScript].concat(args)
    jsonStdinProcess.requestBody = JSON.stringify(jsonObj || {})
    jsonStdinProcess.running = true
    return true
  }

  function refreshControllerMembers(nwid) {
    if (!nwid) return false
    actionStatus = "Loading members…"
    return runMutation(["controller", "members", nwid], "controllerMembers")
  }

  function createControllerNetworkQuick(fields) {
    if (jsonStdinProcess.running) return false
    if (busyAction !== "" && busyAction !== "controllerCreate") return false
    busyAction = "controllerCreate"
    actionStatus = "Creating network…"
    return runApiJsonStdin(["controller", "network", "create"], fields, "controllerNetwork")
  }

  function createControllerNetworkBlank() {
    if (jsonStdinProcess.running) return false
    if (busyAction !== "" && busyAction !== "controllerCreate") return false
    busyAction = "controllerCreate"
    actionStatus = "Creating network…"
    return runMutation(["controller", "network", "create-blank"], "controllerNetwork")
  }

  function updateControllerNetwork(nwid, fields, onDone) {
    if (busyAction !== "") return false
    busyAction = "controllerUpdate"
    actionStatus = "Updating network…"
    return runApiJsonStdin(["controller", "network", "update", nwid], fields, "controllerNetwork", onDone)
  }

  function deleteControllerNetwork(nwid, onDone) {
    if (busyAction !== "") return false
    busyAction = "controllerDelete"
    actionStatus = "Deleting network…"
    pendingControllerNetworkDeleteId = nwid
    return runMutation(["controller", "network", "delete", nwid], "controllerNetworkDelete", onDone)
  }

  function updateControllerMember(nwid, nodeId, fields, onDone) {
    if (busyAction !== "") return false
    busyAction = "memberUpdate"
    actionStatus = "Updating member…"
    return runApiJsonStdin(
      ["controller", "member", "update", nwid, nodeId],
      fields,
      "controllerMember",
      onDone
    )
  }

  function deleteControllerMember(nwid, nodeId, onDone) {
    if (busyAction !== "") return false
    busyAction = "memberDelete"
    actionStatus = "Removing member…"
    pendingMemberDeleteNwid = nwid
    return runMutation(["controller", "member", "delete", nwid, nodeId], "controllerMemberDelete", onDone)
  }

  function authorizeControllerMember(nwid, nodeId, network, members, onDone) {
    return updateControllerMember(nwid, nodeId, Model.authorizeMemberPayload(network, members), onDone)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()
  Component.onCompleted: refreshAll()

  Process {
    id: jsonStdinProcess
    running: false
    stdinEnabled: true
    property string requestBody: ""
    property string kind: ""
    property var done: null
    command: ["/bin/bash", root.apiScript]
    onStarted: {
      write(requestBody + "\n")
      stdinEnabled = false
    }
    onRunningChanged: {
      if (!running) stdinEnabled = true
      root.syncFetching()
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.finishJsonStdin(this.text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var err = String(text || "").trim()
        if (err !== "" && root.busyAction !== "")
          root.actionStatus = err.slice(0, 120)
      }
    }
  }

  Process {
    id: mutationProcess
    running: false
    property string kind: ""
    property var done: null
    onRunningChanged: root.syncFetching()
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.finishMutation(this.text)
    }
  }

  Process {
    id: apiProcess
    running: false
    onRunningChanged: root.syncFetching()
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.finishRefresh(this.text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var err = String(text || "").trim()
        if (err !== "" && root.busyAction === "")
          root.actionStatus = err.slice(0, 120)
      }
    }
  }

  Process {
    id: storeProcess
    running: false
    property string secret: ""
    stdinEnabled: true
    command: ["/bin/bash", root.apiScript, "auth", "store"]
    onStarted: {
      write(secret + "\n")
      stdinEnabled = false
      secret = ""
    }
    onRunningChanged: if (!running) stdinEnabled = true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var env = Model.parseEnvelope(this.text)
        root.applyEnvelope(this.text, "auth")
        if (env.ok && root.authInfo.hasToken) {
          root.errorText = ""
          root.needsAuth = false
          root.tokenRejected = false
          root.actionStatus = "Token saved to keyring"
          root.refreshAll()
        } else {
          root.actionStatus = root.errorText || "Failed to save token"
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var err = String(text || "").trim()
        if (err !== "" && root.actionStatus.indexOf("Failed") < 0)
          root.actionStatus = err.slice(0, 120)
      }
    }
  }

  onOpenedChanged: if (root.opened) root.refreshAll()

  Timer {
    interval: (root.opened ? 10 : root.refreshIntervalSec) * 1000
    running: true
    repeat: true
    triggeredOnStart: false
    onTriggered: root.refreshAll()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    active: root.alerting
    tooltipText: {
      if (!root.everLoaded) return "ZeroTier — loading"
      if (root.needsAuth || !root.authInfo.hasToken) return "ZeroTier — API token required"
      if (root.tokenRejected) return "ZeroTier — token rejected, paste again"
      if (root.errorText !== "") return "ZeroTier: " + root.errorText
      var s = "ZeroTier"
      if (root.nodeAddress !== "") s += " · " + root.displayLabel
      s += " · " + root.joinedCount + " network(s)"
      if (root.okCount > 0) s += " · " + root.okCount + " OK"
      return s
    }
    iconComponent: Component {
      Item {
        anchors.fill: parent

        ZtnodesIcon {
          anchors.centerIn: parent
          iconSize: button.opticalSize
          color: root.barIconColor
          glyphOpacity: root.barIconOpacity
          badgeColor: root.urgent
          warning: root.needsAuth || !root.authInfo.hasToken || root.tokenRejected
        }

        Text {
          visible: root.everLoaded && (root.needsAuth || root.tokenRejected || root.okCount > 0 || root.joinedCount > 0)
          anchors.left: parent.horizontalCenter
          anchors.leftMargin: Style.space(4)
          anchors.top: parent.verticalCenter
          anchors.topMargin: -Style.space(2)
          text: {
            if (root.needsAuth || !root.authInfo.hasToken || root.tokenRejected) return "!"
            if (root.okCount > 0) return String(root.okCount)
            return String(root.joinedCount)
          }
          color: button.active && button.useActiveColor ? button.activeColor : button.foreground
          font.family: button.fontFamily
          font.pixelSize: Math.max(6, button.fontSize - 1)
          renderType: Text.NativeRendering
          textFormat: Text.PlainText
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      else if (buttonCode === Qt.MiddleButton) root.refreshAll()
    }
  }
}
