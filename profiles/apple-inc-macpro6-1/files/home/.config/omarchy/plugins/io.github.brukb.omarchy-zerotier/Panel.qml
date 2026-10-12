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
  moduleName: "io.github.brukb.omarchy-zerotier"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  property string activeTab: "client"
  property string clientView: "networks"
  property int networkIndex: 0
  property var selectedNetwork: null
  property var pendingLeave: null
  property bool joinOpen: false

  property string serverView: "networks"
  property var selectedControllerNetwork: null
  property var selectedControllerMember: null
  property int controllerNetworkIndex: 0
  property bool serverMemberAddOpen: false
  property var pendingDeleteNetwork: null
  property var pendingDeleteMember: null

  property string editNetName: ""
  property string editPoolStart: ""
  property string editPoolEnd: ""
  property string editMtu: "2800"
  property string editMulticastLimit: "32"
  property string editRoutes: ""
  property string editDnsDomain: ""
  property string editDnsServers: ""
  property string editRules: ""
  property bool editPrivate: true
  property bool editBroadcast: true
  property bool editV4ZT: true
  property bool editV6SixPlane: false
  property bool editV6RFC4193: false
  property bool editV6ZT: false
  property string memberIpField: ""
  property string memberNameField: ""
  property string addMemberField: ""

  property bool cursorActive: false
  property string focusSection: "list"
  property int memberIndex: 0
  property int tabIndex: 0
  property int chipIndex: 0
  property int footerIndex: 0
  property int toggleIndex: 0
  property string rulesEditorSource: "create"
  property string rulesEditorText: ""
  property string editRulesNetworkId: ""
  property int formActionIndex: 0
  property int formFieldIndex: 0
  property bool formInputActive: false
  property int rulesEditorReturnFieldIndex: 0

  readonly property var controllerNetworks: hw ? hw.controllerNetworks : []
  readonly property var controllerMembers: hw ? hw.controllerMembers : []
  readonly property color urgent: bar && bar.urgent !== undefined ? bar.urgent : "#cc6666"
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Color.popups.background
  readonly property bool nodeOnline: hw && hw.nodeStatus && hw.nodeStatus.online
  readonly property color iconColor: nodeOnline ? foreground : dim
  readonly property real iconOpacity: nodeOnline ? 1.0 : 0.5
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var hw: hostWidget
  readonly property bool showAuthSetup: hw ? (!hw.authInfo.hasToken || hw.needsAuth || hw.tokenRejected) : true
  readonly property bool confirmOpen:
    pendingLeave !== null || pendingDeleteNetwork !== null || pendingDeleteMember !== null
  readonly property var networks: hw ? hw.networks : []
  readonly property var peers: hw ? hw.peers : []
  readonly property bool controllerActive: hw ? hw.controllerActive : false

  onControllerActiveChanged: {
    if (!controllerActive && activeTab === "server") selectClientTab()
  }

  readonly property bool showClientFooter:
    !showAuthSetup && activeTab === "client" && clientView === "networks"
  readonly property bool showServerFooter:
    !showAuthSetup && activeTab === "server" && serverView === "networks"
  readonly property bool showServerMembersFooter:
    !showAuthSetup && activeTab === "server" && serverView === "members"
  readonly property bool showRulesFooter:
    !showAuthSetup && activeTab === "server" && serverView === "rules"
  readonly property bool showFooter:
    showClientFooter || showServerFooter || showServerMembersFooter || showRulesFooter
  readonly property string subViewTitle: {
    if (clientView === "peers") return "Peers · " + peers.length
    if (clientView === "detail" && selectedNetwork)
      return Model.networkLabel(selectedNetwork)
    return ""
  }

  readonly property string serverSubViewTitle: {
    if (serverView === "members") return "Members · " + controllerMembers.length
    if (serverView === "memberDetail" && selectedControllerMember)
      return Model.memberLabel(selectedControllerMember)
    if (serverView === "detail" && selectedControllerNetwork)
      return Model.controllerNetworkLabel(selectedControllerNetwork)
    if (serverView === "edit" && selectedControllerNetwork)
      return "Edit · " + Model.controllerNetworkLabel(selectedControllerNetwork)
    if (serverView === "create") return "Create network"
    if (serverView === "rules") return "Flow rules"
    return ""
  }

  readonly property string controllerMetaLine: {
    if (!hw || !hw.controllerStatus) return ""
    var v = hw.controllerStatus.apiVersion
    return "Controller API v" + (v !== undefined ? v : "?")
      + " · " + controllerNetworks.length + " network(s)"
  }

  readonly property string statusLine: {
    if (!hw || !hw.everLoaded) return "Loading…"
    if (hw.snapshotFetching) return "Refreshing…"
    if (hw.errorText !== "") return hw.errorText
    if (hw.needsAuth || !hw.authInfo.hasToken) return "API token required"
    if (hw.actionStatus !== "" && hw.busyAction !== "") return hw.actionStatus
    if (hw.showAsOnline) {
      var n = hw.okCount > 0 ? hw.okCount : hw.joinedCount
      return "Online · " + n + " network(s)"
    }
    return "Offline"
  }

  function dismissConfirm() {
    if (pendingLeave !== null) pendingLeave = null
    else if (pendingDeleteNetwork !== null) pendingDeleteNetwork = null
    else if (pendingDeleteMember !== null) pendingDeleteMember = null
  }

  function restorePanelFocus() {
    cursorActive = true
    Qt.callLater(function() {
      keyCatcher.forceActiveFocus()
      scrollNavIntoView()
    })
  }

  function finishServerDeleteNav() {
    backServerToNetworks()
    focusSection = "list"
    chipIndex = 0
    clampNavIndices()
    restorePanelFocus()
  }

  function finishClientLeaveNav() {
    clientView = "networks"
    selectedNetwork = null
    focusSection = "list"
    chipIndex = 0
    clampNavIndices()
    restorePanelFocus()
  }

  function handleConfirmKey(event) {
    var dlg = null
    if (pendingLeave !== null) dlg = leaveConfirm
    else if (pendingDeleteNetwork !== null) dlg = deleteNetworkConfirm
    else if (pendingDeleteMember !== null) dlg = deleteMemberConfirm
    if (!dlg) return false

    if (event.key === Qt.Key_Left || event.key === Qt.Key_Right
        || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab
        || event.text === "h" || event.text === "H"
        || event.text === "l" || event.text === "L") {
      dlg.selectedIndex = dlg.selectedIndex === 0 ? 1 : 0
      return true
    }
    return dlg.handleKey(event)
  }

  function refresh() { if (hw) hw.refreshAll() }

  function clientRowChipCount(net) { return 3 }

  function controllerRowChipCount() { return 2 }

  function memberRowChipCount(mem) {
    return mem && !mem.authorized ? 3 : 2
  }

  function currentRowChipCount() {
    if (activeTab === "client" && clientView === "networks") {
      var net = networks[networkIndex]
      return net ? clientRowChipCount(net) : 0
    }
    if (activeTab === "server" && serverView === "networks") return controllerRowChipCount()
    if (activeTab === "server" && serverView === "members") {
      var mem = controllerMembers[memberIndex]
      return mem ? memberRowChipCount(mem) : 0
    }
    if (activeTab === "client" && clientView === "detail") return 2
    if (activeTab === "server" && serverView === "detail") return 4
    if (activeTab === "server" && serverView === "memberDetail") return 3
    return 0
  }

  function clientFooterButtonCount() { return 2 }

  function serverFooterButtonCount() { return 2 }

  function serverMembersFooterButtonCount() { return 2 }

  function navSectionsForView() {
    if (showAuthSetup) return []
    if (serverView === "rules") return ["back", "editor", "footer"]
    if (activeTab === "client" && clientView === "networks") {
      var sections = ["tabs"]
      if (networks.length > 0) sections.push("list")
      if (showClientFooter) sections.push("footer")
      return sections
    }
    if (activeTab === "server" && serverView === "networks") {
      var s = ["tabs"]
      if (controllerNetworks.length > 0) s.push("list")
      if (showServerFooter) s.push("footer")
      return s
    }
    if (activeTab === "server" && serverView === "members") {
      var m = ["back"]
      if (controllerMembers.length > 0) m.push("list")
      if (showServerMembersFooter) m.push("footer")
      return m
    }
    if (activeTab === "client" && clientView === "detail") return ["back", "toggles", "detailChips"]
    if (activeTab === "client" && clientView === "peers") return ["back"]
    if (activeTab === "server" && serverView === "detail") return ["back", "detailChips"]
    if (activeTab === "server" && serverView === "create") return ["back", "formFields", "formFooter"]
    if (activeTab === "server" && serverView === "edit") return ["back", "formFields", "formFooter"]
    if (activeTab === "server" && serverView === "memberDetail") return ["back", "formFields", "detailChips"]
    return []
  }

  function formFooterButtonCount() {
    if (serverView === "create") return 2
    if (serverView === "edit") return 1
    if (serverView === "rules") return 2
    return 0
  }

  function memberFormFieldCount() {
    var ips = selectedControllerMember && selectedControllerMember.ipAssignments
      ? selectedControllerMember.ipAssignments.length : 0
    return 5 + ips
  }

  function formFieldCount() {
    if (serverView === "create") return 16
    if (serverView === "edit") return 15
    if (serverView === "memberDetail") return memberFormFieldCount()
    return 0
  }

  function isFormFieldHighlighted(i) {
    return cursorActive && !formInputActive && focusSection === "formFields" && formFieldIndex === i
  }

  function focusFormInput(field) {
    if (!field) return
    formInputActive = true
    field.forceActiveFocus()
  }

  function releaseFormInput() {
    formInputActive = false
    Qt.callLater(function() {
      keyCatcher.forceActiveFocus()
      scrollFormFieldIntoView()
    })
  }

  function createFormNavItem(i) {
    switch (i) {
      case 0: return createNavName
      case 1: return createNavPoolStart
      case 2: return createNavPoolEnd
      case 3: return createNavCidr
      case 4: return createNavRoutes
      case 5: return createNavMtu
      case 6: return createNavMulticast
      case 7: return createNavDnsDomain
      case 8: return createNavDnsServers
      case 9: return createNavRules
      case 10: return createNavPrivate
      case 11: return createNavBroadcast
      case 12: return createNavV4
      case 13: return createNavV6Six
      case 14: return createNavV6Rfc
      case 15: return createNavV6Zt
    }
    return null
  }

  function editFormNavItem(i) {
    switch (i) {
      case 0: return editNavName
      case 1: return editNavPoolStart
      case 2: return editNavPoolEnd
      case 3: return editNavMtu
      case 4: return editNavMulticast
      case 5: return editNavRoutes
      case 6: return editNavDnsDomain
      case 7: return editNavDnsServers
      case 8: return editNavRules
      case 9: return editNavPrivate
      case 10: return editNavBroadcast
      case 11: return editNavV4
      case 12: return editNavV6Six
      case 13: return editNavV6Rfc
      case 14: return editNavV6Zt
    }
    return null
  }

  function memberFormNavItem(i) {
    if (i === 0) return memberNavName
    if (i >= 1 && i <= 3 && memberToggleNav) return memberToggleNav.itemAt(i - 1)
    if (i === 4) return memberNavIpRow
    if (i >= 5 && memberIpChipNav) return memberIpChipNav.itemAt(i - 5)
    return null
  }

  function currentFormNavItem() {
    if (serverView === "create") return createFormNavItem(formFieldIndex)
    if (serverView === "edit") return editFormNavItem(formFieldIndex)
    if (serverView === "memberDetail") return memberFormNavItem(formFieldIndex)
    return null
  }

  function scrollFormFieldIntoView() {
    var item = currentFormNavItem()
    if (item) scrollItemIntoView(item)
  }

  function activateCreateFormField(i) {
    switch (i) {
      case 0: focusFormInput(createNameField); return
      case 1: focusFormInput(createPoolStartField); return
      case 2: focusFormInput(createPoolEndField); return
      case 3: focusFormInput(createCidrField); return
      case 4: focusFormInput(createRoutesField); return
      case 5: focusFormInput(createMtuField); return
      case 6: focusFormInput(createMulticastField); return
      case 7: focusFormInput(createDnsDomainField); return
      case 8: focusFormInput(createDnsServersField); return
      case 9: openRulesEditor("create"); return
      case 10: createPrivateSwitch.checked = !createPrivateSwitch.checked; return
      case 11: createBroadcastSwitch.checked = !createBroadcastSwitch.checked; return
      case 12: createV4ZTSwitch.checked = !createV4ZTSwitch.checked; return
      case 13: createV6SixPlaneSwitch.checked = !createV6SixPlaneSwitch.checked; return
      case 14: createV6RFC4193Switch.checked = !createV6RFC4193Switch.checked; return
      case 15: createV6ZTSwitch.checked = !createV6ZTSwitch.checked; return
    }
  }

  function activateEditFormField(i) {
    switch (i) {
      case 0: focusFormInput(editNameField); return
      case 1: focusFormInput(editPoolStartField); return
      case 2: focusFormInput(editPoolEndField); return
      case 3: focusFormInput(editMtuField); return
      case 4: focusFormInput(editMulticastField); return
      case 5: focusFormInput(editRoutesField); return
      case 6: focusFormInput(editDnsDomainField); return
      case 7: focusFormInput(editDnsServersField); return
      case 8: openRulesEditor("edit"); return
      case 9: editPrivate = !editPrivate; return
      case 10: editBroadcast = !editBroadcast; return
      case 11: editV4ZT = !editV4ZT; return
      case 12: editV6SixPlane = !editV6SixPlane; return
      case 13: editV6RFC4193 = !editV6RFC4193; return
      case 14: editV6ZT = !editV6ZT; return
    }
  }

  function activateMemberFormField(i) {
    if (i === 0) focusFormInput(memberNameInput)
    else if (i === 1) updateMember({ authorized: !selectedControllerMember.authorized })
    else if (i === 2) updateMember({ activeBridge: !selectedControllerMember.activeBridge })
    else if (i === 3) updateMember({ noAutoAssignIps: !selectedControllerMember.noAutoAssignIps })
    else if (i === 4) focusFormInput(memberIpInput)
    else if (i >= 5 && selectedControllerMember) {
      var ips = selectedControllerMember.ipAssignments || []
      var ip = ips[i - 5]
      if (ip) removeMemberIp(ip)
    }
  }

  function activateFormField(i) {
    if (serverView === "create") activateCreateFormField(i)
    else if (serverView === "edit") activateEditFormField(i)
    else if (serverView === "memberDetail") activateMemberFormField(i)
  }

  function syncSelectedNetwork() {
    if (!selectedNetwork) return
    var id = Model.plain(selectedNetwork.id)
    for (var i = 0; i < networks.length; i++) {
      if (networks[i].id === id) {
        selectedNetwork = networks[i]
        return
      }
    }
  }

  function patchSelectedNetworkFlag(key, value) {
    if (!selectedNetwork) return
    selectedNetwork = {
      id: selectedNetwork.id,
      name: selectedNetwork.name,
      status: selectedNetwork.status,
      type: selectedNetwork.type,
      mac: selectedNetwork.mac,
      assignedAddresses: selectedNetwork.assignedAddresses,
      portDeviceName: selectedNetwork.portDeviceName,
      allowDNS: key === "allowDNS" ? value : selectedNetwork.allowDNS,
      allowDefault: key === "allowDefault" ? value : selectedNetwork.allowDefault,
      allowGlobal: key === "allowGlobal" ? value : selectedNetwork.allowGlobal,
      allowManaged: key === "allowManaged" ? value : selectedNetwork.allowManaged
    }
  }

  function restoreRulesEditorNav() {
    serverView = rulesEditorSource === "create" ? "create" : "edit"
    cursorActive = true
    focusSection = "formFields"
    formFieldIndex = rulesEditorReturnFieldIndex
    Qt.callLater(function() {
      keyCatcher.forceActiveFocus()
      scrollFormFieldIntoView()
    })
  }

  function enterSubView(section) {
    cursorActive = true
    focusSection = section || "back"
    chipIndex = 0
    toggleIndex = 0
    formActionIndex = 0
    formFieldIndex = 0
    formInputActive = false
  }

  function handleSubViewBack() {
    if (serverView === "rules") cancelRulesEditor()
    else if (activeTab === "client" && clientView === "peers") clientView = "detail"
    else if (activeTab === "client" && clientView === "detail") {
      clientView = "networks"
      selectedNetwork = null
    } else if (activeTab === "server") serverBackAction()
  }

  function clampNavIndices() {
    var chips = currentRowChipCount()
    if (chips > 0) chipIndex = Math.max(0, Math.min(chipIndex, chips - 1))
    else chipIndex = 0
    toggleIndex = Math.max(0, Math.min(toggleIndex, 3))
    tabIndex = activeTab === "server" ? 1 : 0
    var formMax = formFooterButtonCount()
    if (formMax > 0) formActionIndex = Math.max(0, Math.min(formActionIndex, formMax - 1))
    var ffMax = formFieldCount()
    if (ffMax > 0) formFieldIndex = Math.max(0, Math.min(formFieldIndex, ffMax - 1))
    if (activeTab === "client" && clientView === "networks" && showClientFooter)
      footerIndex = Math.max(0, Math.min(footerIndex, clientFooterButtonCount() - 1))
    else if (activeTab === "server" && serverView === "networks" && showServerFooter)
      footerIndex = Math.max(0, Math.min(footerIndex, serverFooterButtonCount() - 1))
    else if (activeTab === "server" && serverView === "members" && showServerMembersFooter)
      footerIndex = Math.max(0, Math.min(footerIndex, serverMembersFooterButtonCount() - 1))
    else if (showRulesFooter)
      footerIndex = Math.max(0, Math.min(footerIndex, 1))
    else footerIndex = 0
    clampListNavIndex()
  }

  function moveVerticalNav(dy) {
    var sections = navSectionsForView()
    if (sections.length === 0) return

    if (focusSection === "toggles" && activeTab === "client" && clientView === "detail") {
      var tNext = toggleIndex + dy
      if (tNext >= 0 && tNext <= 3) {
        toggleIndex = tNext
        scrollNavIntoView()
        return
      }
    }

    if (focusSection === "formFields" && formFieldCount() > 0) {
      var ffNext = formFieldIndex + dy
      var ffCount = formFieldCount()
      if (ffNext >= 0 && ffNext < ffCount) {
        formFieldIndex = ffNext
        scrollFormFieldIntoView()
        return
      }
    }

    if ((focusSection === "list" || focusSection === "rowChips") && listNavCount() > 0) {
      var next = currentListNavIndex() + dy
      var count = listNavCount()
      if (next >= 0 && next < count) {
        focusSection = "list"
        setListNavIndex(next)
        chipIndex = 0
        scrollListNavIntoView()
        return
      }
    }

    var idx = sections.indexOf(focusSection)
    if (idx < 0) idx = 0
    if (dy > 0 && idx < sections.length - 1) {
      focusSection = sections[idx + 1]
      if (focusSection === "list" || focusSection === "detailChips") chipIndex = 0
    } else if (dy < 0 && idx > 0) {
      focusSection = sections[idx - 1]
      if (focusSection === "list" || focusSection === "detailChips") chipIndex = 0
    }
    scrollNavIntoView()
  }

  function scrollNavIntoView() {
    if (focusSection === "list") scrollListNavIntoView()
    else if (focusSection === "footer") {
      if (showClientFooter) scrollItemIntoView(clientFooterRow)
      else if (showServerFooter) scrollItemIntoView(serverFooterRow)
      else if (showServerMembersFooter) scrollItemIntoView(serverMembersFooterRow)
      else if (showRulesFooter) scrollItemIntoView(rulesFooterRow)
    } else if (focusSection === "tabs") scrollItemIntoView(modeTabs)
    else if (focusSection === "back") {
      if (activeTab === "client") scrollItemIntoView(clientBackBtn)
      else scrollItemIntoView(serverBackBtn)
    } else if (focusSection === "toggles" && toggleRepeater)
      scrollItemIntoView(toggleRepeater.itemAt(toggleIndex))
    else if (focusSection === "editor" && rulesEditorBox)
      scrollItemIntoView(rulesEditorBox)
    else if (focusSection === "formFields")
      scrollFormFieldIntoView()
    else if (focusSection === "formFooter") {
      if (serverView === "create") scrollItemIntoView(createFormFooter)
      else if (serverView === "edit") scrollItemIntoView(editSaveBtn)
    } else if (focusSection === "detailChips") {
      if (activeTab === "client" && clientView === "detail") scrollItemIntoView(clientDetailChips)
      else if (activeTab === "server" && serverView === "detail") scrollItemIntoView(serverDetailChips)
      else if (activeTab === "server" && serverView === "memberDetail") scrollItemIntoView(memberDetailChips)
    }
  }

  function listNavActive() {
    return !showAuthSetup && (
      (activeTab === "client" && clientView === "networks")
      || (activeTab === "server" && (serverView === "networks" || serverView === "members"))
    )
  }

  function listNavCount() {
    if (activeTab === "client") return networks.length
    if (serverView === "members") return controllerMembers.length
    return controllerNetworks.length
  }

  function clampListNavIndex() {
    var n = listNavCount()
    if (n === 0) return
    if (activeTab === "client") networkIndex = Math.max(0, Math.min(networkIndex, n - 1))
    else if (serverView === "members") memberIndex = Math.max(0, Math.min(memberIndex, n - 1))
    else controllerNetworkIndex = Math.max(0, Math.min(controllerNetworkIndex, n - 1))
  }

  function currentListNavIndex() {
    if (activeTab === "client") return networkIndex
    if (serverView === "members") return memberIndex
    return controllerNetworkIndex
  }

  function setListNavIndex(i) {
    if (activeTab === "client") networkIndex = i
    else if (serverView === "members") memberIndex = i
    else controllerNetworkIndex = i
  }

  function scrollItemIntoView(item) {
    if (!scroller || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var point = item.mapToItem(scroller.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = scroller.contentY
      var viewBottom = viewTop + scroller.height
      var maxY = Math.max(0, scroller.contentHeight - scroller.height)
      if (top < viewTop + margin) scroller.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) scroller.contentY = Math.min(maxY, bottom + margin - scroller.height)
    })
  }

  function scrollListNavIntoView() {
    var col = null
    var idx = currentListNavIndex()
    if (activeTab === "client" && clientView === "networks") col = clientNetworkList
    else if (serverView === "networks") col = serverNetworkList
    else if (serverView === "members") col = serverMemberList
    if (!col || idx < 0 || idx >= col.children.length) return
    scrollItemIntoView(col.children[idx])
  }

  function handleMove(dx, dy) {
    if (showAuthSetup) return
    if (confirmOpen) return
    if (formInputActive) return
    if (serverView === "rules" && rulesEditorField.activeFocus) return
    cursorActive = true
    clampNavIndices()

    if (dx !== 0) {
      if (focusSection === "list" || focusSection === "rowChips") {
        var chips = currentRowChipCount()
        if (chips === 0) return
        focusSection = "rowChips"
        chipIndex = Math.max(0, Math.min(chipIndex + dx, chips - 1))
        return
      }
      if (focusSection === "footer") {
        var maxF = 0
        if (showRulesFooter) maxF = 2
        else if (showClientFooter) maxF = clientFooterButtonCount()
        else if (showServerFooter) maxF = serverFooterButtonCount()
        else if (showServerMembersFooter) maxF = serverMembersFooterButtonCount()
        if (maxF > 0) footerIndex = Math.max(0, Math.min(footerIndex + dx, maxF - 1))
        return
      }
      if (focusSection === "formFooter" && serverView === "create") {
        formActionIndex = Math.max(0, Math.min(formActionIndex + dx, 1))
        return
      }
      if (focusSection === "tabs" && controllerActive) {
        if (dx > 0) selectServerTab()
        else selectClientTab()
      }
      if (focusSection === "detailChips") {
        var dc = currentRowChipCount()
        if (dc > 0) chipIndex = Math.max(0, Math.min(chipIndex + dx, dc - 1))
      }
      return
    }

    if (dy !== 0) moveVerticalNav(dy)
  }

  function activateClientRowChip(rowIdx, chip) {
    var net = networks[rowIdx]
    if (!net) return
    if (chip === 0) openDetail(net)
    else if (chip === 1) copyText((net.assignedAddresses && net.assignedAddresses[0]) || "")
    else toggleClientNetworkConnection(net)
  }

  function activateControllerRowChip(chip) {
    var cn = controllerNetworks[controllerNetworkIndex]
    if (!cn) return
    if (chip === 0) openControllerDetail(cn)
    else copyText(cn.id)
  }

  function activateMemberRowChip(chip) {
    var mem = controllerMembers[memberIndex]
    if (!mem) return
    if (chip === 0) openMemberDetail(mem)
    else if (chip === 1) copyText(mem.address)
    else if (!mem.authorized && hw && selectedControllerNetwork)
      hw.authorizeControllerMember(
        selectedControllerNetwork.id,
        mem.address,
        selectedControllerNetwork,
        controllerMembers,
        function(ok) { if (ok) hw.refreshControllerMembers(selectedControllerNetwork.id) }
      )
  }

  function activateCursor() {
    if (showAuthSetup) return
    cursorActive = true
    clampNavIndices()

    if (serverView === "rules") {
      if (focusSection === "back") cancelRulesEditor()
      else if (focusSection === "footer") {
        if (footerIndex === 0) saveRulesEditor()
        else cancelRulesEditor()
      } else if (focusSection === "editor" && rulesEditorField)
        rulesEditorField.forceActiveFocus()
      return
    }

    if (activeTab === "client" && clientView === "networks") {
      if (focusSection === "tabs") {
        if (tabIndex === 0) selectClientTab()
        else selectServerTab()
      } else if (focusSection === "footer") {
        if (footerIndex === 0) { clientView = "peers"; joinOpen = false }
        else joinOpen = !joinOpen
      } else if (focusSection === "rowChips") activateClientRowChip(networkIndex, chipIndex)
      else if (focusSection === "list" && networks.length > 0) openDetail(networks[networkIndex])
      return
    }

    if (activeTab === "server" && serverView === "networks") {
      if (focusSection === "tabs") {
        if (tabIndex === 0) selectClientTab()
        else selectServerTab()
      } else if (focusSection === "footer") {
        if (footerIndex === 0 && hw) hw.refreshControllerNetworks()
        else openServerCreate()
      } else if (focusSection === "rowChips") activateControllerRowChip(chipIndex)
      else if (focusSection === "list" && controllerNetworks.length > 0)
        openControllerDetail(controllerNetworks[controllerNetworkIndex])
      return
    }

    if (activeTab === "server" && serverView === "members") {
      if (focusSection === "back") backServerFromMembers()
      else if (focusSection === "footer") {
        if (footerIndex === 0 && hw && selectedControllerNetwork)
          hw.refreshControllerMembers(selectedControllerNetwork.id)
        else serverMemberAddOpen = !serverMemberAddOpen
      } else if (focusSection === "rowChips") activateMemberRowChip(chipIndex)
      else if (focusSection === "list" && controllerMembers.length > 0)
        openMemberDetail(controllerMembers[memberIndex])
      return
    }

    if (activeTab === "client" && clientView === "detail") {
      if (focusSection === "back") { clientView = "networks"; selectedNetwork = null }
      else if (focusSection === "toggles" && hw && selectedNetwork) {
        var keys = ["allowDNS", "allowDefault", "allowGlobal", "allowManaged"]
        var key = keys[toggleIndex]
        var val = false
        if (key === "allowDNS") val = !selectedNetwork.allowDNS
        else if (key === "allowDefault") val = !selectedNetwork.allowDefault
        else if (key === "allowGlobal") val = !selectedNetwork.allowGlobal
        else val = !selectedNetwork.allowManaged
        patchSelectedNetworkFlag(key, val)
        hw.setNetworkFlag(selectedNetwork.id, key, val)
      } else if (focusSection === "detailChips") {
        if (chipIndex === 0) copyText(selectedNetwork ? selectedNetwork.id : "")
        else pendingLeave = selectedNetwork
      }
      return
    }

    if (activeTab === "client" && clientView === "peers") {
      clientView = "detail"
      return
    }

    if (activeTab === "server" && serverView === "detail") {
      if (focusSection === "back") backServerToNetworks()
      else if (focusSection === "detailChips") {
        if (chipIndex === 0) copyText(selectedControllerNetwork ? selectedControllerNetwork.id : "")
        else if (chipIndex === 1) openControllerMembers()
        else if (chipIndex === 2) openControllerEdit()
        else pendingDeleteNetwork = selectedControllerNetwork
      }
      return
    }

    if (activeTab === "server" && serverView === "create") {
      if (focusSection === "back") serverBackAction()
      else if (focusSection === "formFields") activateFormField(formFieldIndex)
      else if (focusSection === "formFooter") {
        if (formActionIndex === 0) submitNetworkCreate()
        else submitBlankNetworkCreate()
      }
      return
    }

    if (activeTab === "server" && serverView === "edit") {
      if (focusSection === "back") serverBackAction()
      else if (focusSection === "formFields") activateFormField(formFieldIndex)
      else if (focusSection === "formFooter") submitNetworkUpdate()
      return
    }

    if (activeTab === "server" && serverView === "memberDetail") {
      if (focusSection === "back") backServerFromMembers()
      else if (focusSection === "formFields") activateFormField(formFieldIndex)
      else if (focusSection === "detailChips") {
        if (chipIndex === 0) updateMember({ name: memberNameField })
        else if (chipIndex === 1) copyText(selectedControllerMember ? selectedControllerMember.address : "")
        else pendingDeleteMember = selectedControllerMember
      }
      return
    }

  }

  function handleTextKey(t) {
    if (confirmOpen) return
    if (t === "b" || t === "B") {
      handleSubViewBack()
      return
    }
    if (serverView === "rules" && !rulesEditorField.activeFocus) {
      if (t === "s" || t === "S") {
        saveRulesEditor()
        return
      }
    }
    if (t === "r" || t === "R") refresh()
    else if ((t === "n" || t === "N") && activeTab === "server" && serverView === "networks" && !showAuthSetup)
      openServerCreate()
    else if ((t === "j" || t === "J") && activeTab === "client" && clientView === "networks" && !joinOpen)
      joinOpen = true
    else if ((t === "p" || t === "P") && activeTab === "client" && clientView === "networks")
      clientView = "peers"
  }

  function handlePanelClose() {
    if (confirmOpen) {
      dismissConfirm()
      return
    }
    if (formInputActive) {
      releaseFormInput()
      return
    }
    if (serverView === "rules") {
      cancelRulesEditor()
      return
    }
    if (activeTab === "client" && clientView !== "networks") {
      if (clientView === "peers") clientView = "detail"
      else { clientView = "networks"; selectedNetwork = null }
      return
    }
    if (activeTab === "server" && serverView !== "networks") {
      serverBackAction()
      return
    }
    close()
  }

  function focusListRow(index) {
    cursorActive = true
    focusSection = "list"
    chipIndex = 0
    if (activeTab === "server" && serverView === "members") memberIndex = index
    else setListNavIndex(index)
  }

  function toggleClientNetworkConnection(net) {
    if (!hw || !net) return
    hw.setNetworkFlag(net.id, "allowManaged", !Model.isClientNetworkConnected(net))
  }

  function openRulesEditor(source) {
    rulesEditorSource = source
    rulesEditorReturnFieldIndex = formFieldIndex
    var stored = source === "create" ? createRulesField.text : editRules
    if (stored.trim() === "") {
      if (source === "create") rulesEditorText = Model.defaultFlowRulesText()
      else if (selectedControllerNetwork)
        rulesEditorText = Model.rulesEditorTextFromNetwork(selectedControllerNetwork)
      else rulesEditorText = Model.defaultFlowRulesText()
    } else {
      rulesEditorText = stored
    }
    serverView = "rules"
    cursorActive = true
    focusSection = "back"
    formInputActive = false
    scroller.contentY = 0
    Qt.callLater(function() {
      if (rulesEditorField) rulesEditorField.text = rulesEditorText
      keyCatcher.forceActiveFocus()
    })
  }

  function saveRulesEditor() {
    if (rulesEditorSource === "create") createRulesField.text = rulesEditorText
    else editRules = rulesEditorText
    restoreRulesEditorNav()
  }

  function cancelRulesEditor() {
    restoreRulesEditorNav()
  }

  function selectClientTab() {
    activeTab = "client"
    tabIndex = 0
    clientView = "networks"
    selectedNetwork = null
    joinOpen = false
  }

  function selectServerTab() {
    activeTab = "server"
    tabIndex = 1
    joinOpen = false
    serverMemberAddOpen = false
    serverView = "networks"
    selectedControllerNetwork = null
    selectedControllerMember = null
    if (hw) hw.refreshControllerNetworks()
  }

  function backServerToNetworks() {
    serverView = "networks"
    selectedControllerNetwork = null
    selectedControllerMember = null
    editRulesNetworkId = ""
  }

  function backServerFromMembers() {
    serverView = "detail"
    selectedControllerMember = null
  }

  function openControllerDetail(net) {
    selectedControllerNetwork = net
    serverView = "detail"
    enterSubView("back")
  }

  function openControllerMembers() {
    if (!selectedControllerNetwork) return
    serverView = "members"
    enterSubView("back")
    if (hw) hw.refreshControllerMembers(selectedControllerNetwork.id)
  }

  function openMemberDetail(mem) {
    selectedControllerMember = mem
    memberNameField = Model.plain(mem.name)
    memberIpField = ""
    serverView = "memberDetail"
    enterSubView("formFields")
  }

  function serverBackAction() {
    if (serverView === "rules") cancelRulesEditor()
    else if (serverView === "memberDetail") backServerFromMembers()
    else if (serverView === "members") backServerFromMembers()
    else if (serverView === "edit") serverView = "detail"
    else backServerToNetworks()
  }

  function openServerCreate() {
    populateCreateDefaults()
    serverView = "create"
    scroller.contentY = 0
    enterSubView("formFields")
  }

  function syncSelectedControllerNetwork() {
    if (!selectedControllerNetwork || !hw) return
    var id = Model.plain(selectedControllerNetwork.id)
    for (var i = 0; i < controllerNetworks.length; i++) {
      if (controllerNetworks[i].id === id) {
        selectedControllerNetwork = controllerNetworks[i]
        return
      }
    }
  }

  function syncSelectedControllerMember() {
    if (!selectedControllerMember || !hw) return
    var addr = Model.plain(selectedControllerMember.address)
    for (var i = 0; i < controllerMembers.length; i++) {
      if (controllerMembers[i].address === addr) {
        selectedControllerMember = controllerMembers[i]
        return
      }
    }
  }

  function openControllerEdit() {
    if (!selectedControllerNetwork) return
    var nid = Model.plain(selectedControllerNetwork.id)
    editNetName = Model.plain(selectedControllerNetwork.name)
    var pool = selectedControllerNetwork.ipAssignmentPools
      && selectedControllerNetwork.ipAssignmentPools.length
      ? selectedControllerNetwork.ipAssignmentPools[0]
      : null
    editPoolStart = pool ? Model.plain(pool.ipRangeStart) : ""
    editPoolEnd = pool ? Model.plain(pool.ipRangeEnd) : ""
    editMtu = String(selectedControllerNetwork.mtu || 2800)
    editMulticastLimit = String(selectedControllerNetwork.multicastLimit || 32)
    editRoutes = Model.controllerRoutesToString(selectedControllerNetwork.routes)
    editDnsDomain = Model.plain(selectedControllerNetwork.dns ? selectedControllerNetwork.dns.domain : "")
    editDnsServers = Model.joinAddresses(selectedControllerNetwork.dns ? selectedControllerNetwork.dns.servers : [])
    if (editRulesNetworkId !== nid) {
      editRules = Model.rulesEditorTextFromNetwork(selectedControllerNetwork)
      editRulesNetworkId = nid
    }
    editPrivate = selectedControllerNetwork.private
    editBroadcast = selectedControllerNetwork.enableBroadcast
    editV4ZT = selectedControllerNetwork.v4AssignZT
    editV6SixPlane = selectedControllerNetwork.v6AssignSixPlane
    editV6RFC4193 = selectedControllerNetwork.v6AssignRFC4193
    editV6ZT = selectedControllerNetwork.v6AssignZT
    serverView = "edit"
    enterSubView("formFields")
  }

  function gatherCreatePayload() {
    var plan = Model.suggestControllerNetworkPlan(controllerNetworks)
    return Model.controllerNetworkFormPayload({
      plan: plan,
      name: createNameField.text.trim(),
      poolStart: createPoolStartField.text.trim(),
      poolEnd: createPoolEndField.text.trim(),
      cidr: createCidrField.text.trim(),
      routes: createRoutesField.text.trim(),
      mtu: createMtuField.text.trim(),
      multicastLimit: createMulticastField.text.trim(),
      dnsDomain: createDnsDomainField.text.trim(),
      dnsServers: createDnsServersField.text.trim(),
      rules: createRulesField.text.trim(),
      private: createPrivateSwitch.checked,
      enableBroadcast: createBroadcastSwitch.checked,
      v4ZT: createV4ZTSwitch.checked,
      v6SixPlane: createV6SixPlaneSwitch.checked,
      v6RFC4193: createV6RFC4193Switch.checked,
      v6ZT: createV6ZTSwitch.checked
    })
  }

  function submitNetworkCreate() {
    if (!hw) return
    var ok = hw.createControllerNetworkQuick(gatherCreatePayload())
    if (!ok) {
      hw.actionStatus = "Busy — try again in a moment"
      return
    }
    backServerToNetworks()
    createNameField.text = ""
    createPoolStartField.text = ""
    createPoolEndField.text = ""
    createCidrField.text = ""
    createRoutesField.text = ""
    createMtuField.text = ""
    createMulticastField.text = ""
    createDnsDomainField.text = ""
    createDnsServersField.text = ""
    createRulesField.text = ""
  }

  function populateCreateDefaults() {
    var plan = Model.suggestControllerNetworkPlan(controllerNetworks)
    if (createPoolStartField.text.trim() === "")
      createPoolStartField.text = plan.poolStart
    if (createPoolEndField.text.trim() === "")
      createPoolEndField.text = plan.poolEnd
    if (createCidrField.text.trim() === "")
      createCidrField.text = plan.cidr
    if (createRoutesField.text.trim() === "")
      createRoutesField.text = plan.routes
    if (createMtuField.text.trim() === "")
      createMtuField.text = plan.mtu
    if (createMulticastField.text.trim() === "")
      createMulticastField.text = plan.multicastLimit
    if (createDnsDomainField.text.trim() === "")
      createDnsDomainField.text = plan.dnsDomain
    if (createDnsServersField.text.trim() === "")
      createDnsServersField.text = plan.dnsServers
    if (createRulesField.text.trim() === "")
      createRulesField.text = Model.defaultFlowRulesText()
    createPrivateSwitch.checked = true
    createBroadcastSwitch.checked = true
    createV4ZTSwitch.checked = true
    createV6SixPlaneSwitch.checked = false
    createV6RFC4193Switch.checked = false
    createV6ZTSwitch.checked = false
  }

  function submitBlankNetworkCreate() {
    if (!hw) return
    var ok = hw.createControllerNetworkBlank()
    if (!ok) {
      hw.actionStatus = "Busy — try again in a moment"
      return
    }
    backServerToNetworks()
  }

  function submitNetworkUpdate() {
    if (!hw || !selectedControllerNetwork) return
    var payload = Model.controllerNetworkFormPayload({
      net: selectedControllerNetwork,
      name: editNetName,
      poolStart: editPoolStart,
      poolEnd: editPoolEnd,
      mtu: editMtu,
      multicastLimit: editMulticastLimit,
      routes: editRoutes,
      dnsDomain: editDnsDomain,
      dnsServers: editDnsServers,
      rules: editRules,
      private: editPrivate,
      enableBroadcast: editBroadcast,
      v4ZT: editV4ZT,
      v6SixPlane: editV6SixPlane,
      v6RFC4193: editV6RFC4193,
      v6ZT: editV6ZT
    })
    hw.updateControllerNetwork(selectedControllerNetwork.id, payload, function(ok) {
      if (ok) {
        syncSelectedControllerNetwork()
        serverView = "detail"
      }
    })
  }

  function updateMember(overrides) {
    if (!hw || !selectedControllerNetwork || !selectedControllerMember) return
    var payload = Model.controllerMemberUpdatePayload(selectedControllerMember, overrides)
    hw.updateControllerMember(
      selectedControllerNetwork.id,
      selectedControllerMember.address,
      payload,
      function(ok) { if (ok) syncSelectedControllerMember() }
    )
  }

  function submitAddMember() {
    var node = addMemberField.trim().toLowerCase()
    if (!hw || !selectedControllerNetwork || !/^[0-9a-f]{10}$/.test(node)) return
    hw.authorizeControllerMember(
      selectedControllerNetwork.id,
      node,
      selectedControllerNetwork,
      controllerMembers,
      function(ok) {
      if (ok) {
        addMemberField = ""
        serverMemberAddOpen = false
        hw.refreshControllerMembers(selectedControllerNetwork.id)
      }
    })
  }

  function submitAddMemberIp() {
    var ip = memberIpField.trim()
    if (!ip || !selectedControllerMember) return
    updateMember({ ipAssignments: Model.mergeMemberIp(selectedControllerMember, ip) })
    memberIpField = ""
  }

  function removeMemberIp(ip) {
    if (!selectedControllerMember) return
    updateMember({ ipAssignments: Model.removeMemberIp(selectedControllerMember, ip) })
  }

  function backToNetworks() {
    clientView = "networks"
    selectedNetwork = null
    joinOpen = false
  }

  function copyText(value) {
    var text = Model.plain(value)
    if (text === "") return
    Quickshell.execDetached(["wl-copy", text])
    if (hw) hw.actionStatus = "Copied"
  }

  function openDetail(net) {
    selectedNetwork = net
    clientView = "detail"
    joinOpen = false
    enterSubView("back")
  }

  function leaveMessage(net) {
    if (!net) return "Leave this network?"
    return "Leave network " + Model.plain(net.id) + "?\nName: " + Model.networkLabel(net).slice(0, 48)
  }

  function submitJoin() {
    if (hw && /^[0-9a-fA-F]{16}$/.test(joinField.text.trim()))
      hw.joinNetwork(joinField.text.trim().toLowerCase())
    joinOpen = false
    joinField.text = ""
  }

  component ActionChip: BorderSurface {
    id: chip
    property string label: ""
    property bool chipActive: false
    property bool hovered: false
    signal activated()

    height: Style.space(30)
    width: Math.max(Style.space(56), labelText.implicitWidth + Style.space(20))
    color: chipActive ? selectedFill : (hovered ? hoverFill : "transparent")
    borderSpec: Border.flat(chipActive || hovered ? Color.accent : Util.alpha(foreground, 0.35), Style.normalBorderWidth)
    radius: 0

    Text {
      id: labelText
      anchors.centerIn: parent
      text: chip.label
      color: chipActive || hovered ? Color.accent : foreground
      font.family: fontFamily
      font.pixelSize: Style.font.caption
      textFormat: Text.PlainText
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: chip.hovered = containsMouse
      onClicked: chip.activated()
    }
  }

  component FormTextField: TextField {
    onActiveFocusChanged: root.formInputActive = activeFocus
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) {
        root.releaseFormInput()
        event.accepted = true
      }
    }
  }

  component FormNavRow: Rectangle {
    property bool highlighted: false
    width: parent.width
    radius: Style.cornerRadius
    color: highlighted ? hoverFill : "transparent"
    implicitHeight: Math.max(Style.space(8), slot.childrenRect.height + Style.space(8))
    default property alias content: slot.data

    Item {
      id: slot
      width: parent.width - Style.space(8)
      anchors.centerIn: parent
      implicitHeight: childrenRect.height
    }
  }

  component ConfigField: Rectangle {
    id: cfg
    width: parent.width
    radius: Style.cornerRadius
    property bool navHighlighted: false
    color: navHighlighted ? hoverFill : "transparent"
    implicitHeight: inner.implicitHeight + Style.space(8)
    property string label: ""
    property string hint: ""
    default property alias content: slot.data

    Column {
      id: inner
      width: parent.width - Style.space(8)
      anchors.centerIn: parent
      spacing: Style.space(2)

    Text {
      width: parent.width
      visible: cfg.label !== ""
      text: cfg.label
      color: foreground
      font.family: fontFamily
      font.pixelSize: Style.font.bodySmall
      textFormat: Text.PlainText
    }
    Text {
      width: parent.width
      visible: cfg.hint !== ""
      wrapMode: Text.WordWrap
      text: cfg.hint
      color: dim
      font.family: fontFamily
      font.pixelSize: Style.font.caption
      textFormat: Text.PlainText
    }
    Item {
      id: slot
      width: parent.width
      implicitHeight: childrenRect.height
    }
    }
  }

  Connections {
    target: hw
    function onNetworksChanged() { root.syncSelectedNetwork() }
  }

  Connections {
    target: root
    function onConfirmOpenChanged() {
      if (root.confirmOpen)
        Qt.callLater(function() { confirmKeyFocus.forceActiveFocus() })
      else
        root.restorePanelFocus()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: root.confirmOpen ? confirmKeyFocus : keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(
      column.implicitHeight + (showFooter ? footerBar.height + Style.space(8) : 0),
      Style.space(560)
    )

    onOpenChanged: if (open) {
      root.cursorActive = false
      root.focusSection = "list"
      scroller.contentY = 0
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: confirmOpen || formInputActive || (serverView === "rules" && rulesEditorField.activeFocus)
      onMoveRequested: function(dx, dy) { root.handleMove(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: {
        if (root.confirmOpen) root.dismissConfirm()
        else root.handlePanelClose()
      }
      onTabRequested: function(direction) {
        if (controllerActive && serverView !== "rules") {
          if (direction > 0) root.selectServerTab()
          else root.selectClientTab()
        }
      }
      onTextKey: function(t) { root.handleTextKey(t) }

    Item {
      anchors.fill: parent

      Flickable {
        id: scroller
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: showFooter ? footerBar.top : parent.bottom
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: scroller.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "ZeroTier"
            meta: root.statusLine
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.iconOpacity
            iconComponent: Component {
              ZtnodesIcon {
                iconSize: Style.font.display
                color: root.iconColor
                glyphOpacity: root.iconOpacity
                badgeColor: root.urgent
                warning: hw && (hw.needsAuth || hw.tokenRejected)
              }
            }
            trailingControl: Component {
              PanelActionButton {
                iconText: "󰑐"
                tooltipText: "Refresh"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.refresh()
              }
            }
          }

          Text {
            width: parent.width
            visible: hw && hw.nodeAddress !== ""
            color: dim
            font.family: fontFamily
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: "Node " + (hw ? hw.nodeAddress : "")
              + (hw && hw.nodeStatus ? " · v" + Model.plain(hw.nodeStatus.version) : "")
          }

          Rectangle {
            width: parent.width
            visible: showAuthSetup
            radius: Style.cornerRadius
            color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.06)
            implicitHeight: authCol.implicitHeight + Style.space(16)

            Column {
              id: authCol
              width: parent.width - Style.space(24)
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
              anchors.topMargin: Style.space(12)
              spacing: Style.space(8)

              Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: foreground
                font.family: fontFamily
                font.pixelSize: Style.font.caption
                textFormat: Text.PlainText
                text: hw && hw.tokenRejected
                  ? "Saved token rejected by zerotier-one. Clear and paste the exact 24-character value from authtoken.secret (no spaces or brackets)."
                  : "Paste API token once — stored in OS keyring (secret-service), never in this plugin. Terminal: sudo cat /var/lib/zerotier-one/authtoken.secret"
              }

              TextField {
                id: tokenField
                width: parent.width
                placeholderText: "authtoken"
                echoMode: TextInput.Password
                font.family: fontFamily
                color: foreground
              }

              Flow {
                width: parent.width
                spacing: Style.space(6)
                ActionChip {
                  label: "Save"
                  onActivated: {
                    if (hw) hw.storeToken(tokenField.text.trim())
                    tokenField.text = ""
                  }
                }
                ActionChip { label: "Clear saved"; onActivated: { if (hw) hw.clearToken() } }
              }
            }
          }

          // Client / Server — full-width tabs (agents provider switch pattern).
          Row {
            id: modeTabs
            visible: !showAuthSetup && controllerActive
            width: parent.width
            spacing: Style.spacing.md

            readonly property int tabCount: controllerActive ? 2 : 1
            readonly property real cellWidth: tabCount > 0
              ? (width - spacing * (tabCount - 1)) / tabCount
              : width

            Button {
              width: modeTabs.cellWidth
              text: "Client"
              selected: activeTab === "client"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              hasCursor: root.cursorActive && root.focusSection === "tabs" && root.tabIndex === 0
              onClicked: root.selectClientTab()
            }

            Button {
              visible: controllerActive
              width: modeTabs.cellWidth
              text: "Server"
              selected: activeTab === "server"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              hasCursor: root.cursorActive && root.focusSection === "tabs" && root.tabIndex === 1
              onClicked: root.selectServerTab()
            }
          }

          // Client sub-view back row.
          Row {
            width: parent.width
            visible: !showAuthSetup && activeTab === "client" && clientView !== "networks"
            spacing: Style.space(8)

            Button {
              id: clientBackBtn
              text: "Back"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              verticalPadding: Style.spacing.controlPaddingY
              hasCursor: root.cursorActive && root.focusSection === "back" && activeTab === "client"
              onClicked: root.handleSubViewBack()
            }

            Text {
              width: parent.width - clientBackBtn.implicitWidth - parent.spacing
              anchors.verticalCenter: parent.verticalCenter
              text: root.subViewTitle
              color: foreground
              font.family: fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
              textFormat: Text.PlainText
            }
          }

          // Server sub-view back row.
          Row {
            width: parent.width
            visible: !showAuthSetup && activeTab === "server" && serverView !== "networks"
            spacing: Style.space(8)

            Button {
              id: serverBackBtn
              text: "Back"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              verticalPadding: Style.spacing.controlPaddingY
              hasCursor: root.cursorActive && root.focusSection === "back" && activeTab === "server"
              onClicked: root.serverBackAction()
            }

            Text {
              width: parent.width - serverBackBtn.implicitWidth - parent.spacing
              anchors.verticalCenter: parent.verticalCenter
              text: root.serverSubViewTitle
              color: foreground
              font.family: fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
              textFormat: Text.PlainText
            }
          }

          Column {
            id: clientNetworkList
            width: parent.width
            visible: !showAuthSetup && activeTab === "client" && clientView === "networks"
            spacing: Style.space(8)

            Repeater {
              model: networks
              delegate: NetworkRow {
                width: column.width
                net: modelData
                rowIndex: index
                selected: index === networkIndex
                onOpen: { networkIndex = index; openDetail(modelData) }
                onToggleConnection: toggleClientNetworkConnection(modelData)
                onCopyIp: copyText((modelData.assignedAddresses && modelData.assignedAddresses[0]) || "")
              }
            }

            Text {
              width: parent.width
              visible: networks.length === 0
              horizontalAlignment: Text.AlignHCenter
              color: dim
              font.family: fontFamily
              text: "No joined networks"
              textFormat: Text.PlainText
            }

            Text {
              width: parent.width
              visible: networks.length > 0
              wrapMode: Text.WordWrap
              color: dim
              font.family: fontFamily
              font.pixelSize: Style.font.caption
              text: "↑↓ j/k rows · ←→ h/l actions · tab switch · p peers · j join · r refresh"
              textFormat: Text.PlainText
            }
          }

          Column {
            width: parent.width
            visible: !showAuthSetup && activeTab === "client" && clientView === "detail" && selectedNetwork
            spacing: Style.space(8)

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              color: dim
              font.family: fontFamily
              font.pixelSize: Style.font.caption
              textFormat: Text.PlainText
              text: Model.plain(selectedNetwork.id) + "\n"
                + Model.plain(selectedNetwork.status) + " · " + Model.plain(selectedNetwork.type)
                + " · " + Model.clientNetworkConnectionSummary(selectedNetwork)
            }

            Column {
              id: clientDetailToggles
              width: parent.width
              spacing: Style.space(2)

              Repeater {
                id: toggleRepeater
                model: [
                  { key: "allowDNS", label: "Allow DNS", value: selectedNetwork ? selectedNetwork.allowDNS : false },
                  { key: "allowDefault", label: "Default route", value: selectedNetwork ? selectedNetwork.allowDefault : false },
                  { key: "allowGlobal", label: "Global IPs", value: selectedNetwork ? selectedNetwork.allowGlobal : false },
                  { key: "allowManaged", label: "Managed IPs", value: selectedNetwork ? selectedNetwork.allowManaged : false }
                ]
                delegate: Rectangle {
                  width: column.width
                  radius: Style.cornerRadius
                  color: root.cursorActive && root.focusSection === "toggles" && root.toggleIndex === index
                    ? hoverFill : "transparent"
                  implicitHeight: toggleRow.implicitHeight + Style.space(8)

                  Row {
                    id: toggleRow
                    width: parent.width - Style.space(8)
                    anchors.centerIn: parent
                    spacing: Style.space(8)
                    Text {
                      width: parent.width - toggleSwitch.implicitWidth - parent.spacing
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.label
                      color: foreground
                      font.family: fontFamily
                      font.pixelSize: Style.font.body
                      textFormat: Text.PlainText
                    }
                    Switch {
                      id: toggleSwitch
                      anchors.verticalCenter: parent.verticalCenter
                      checked: modelData.value
                      enabled: hw && selectedNetwork
                      onToggled: {
                        if (hw && selectedNetwork)
                          hw.setNetworkFlag(selectedNetwork.id, modelData.key, checked)
                      }
                    }
                  }
                }
              }
            }

            Flow {
              id: clientDetailChips
              width: parent.width
              spacing: Style.space(6)
              ActionChip {
                label: "Copy ID"
                chipActive: root.cursorActive && root.focusSection === "detailChips" && root.chipIndex === 0
                onActivated: copyText(selectedNetwork ? selectedNetwork.id : "")
              }
              ActionChip {
                label: "Leave network"
                chipActive: root.cursorActive && root.focusSection === "detailChips" && root.chipIndex === 1
                onActivated: pendingLeave = selectedNetwork
              }
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              color: dim
              font.family: fontFamily
              font.pixelSize: Style.font.caption
              text: "↑↓ toggles/chips · ←→ chips · enter toggle/action · b back · esc back"
              textFormat: Text.PlainText
            }
          }

          Column {
            width: parent.width
            visible: !showAuthSetup && activeTab === "client" && clientView === "peers"
            spacing: Style.space(6)
            Repeater {
              model: peers
              delegate: Rectangle {
                width: column.width
                radius: Style.cornerRadius
                color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.04)
                implicitHeight: peerCol.implicitHeight + Style.space(10)
                Column {
                  id: peerCol
                  width: parent.width - Style.space(16)
                  anchors.centerIn: parent
                  spacing: Style.space(2)
                  Text {
                    width: parent.width
                    text: Model.plain(modelData.address)
                    color: foreground
                    font.family: fontFamily
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width
                    text: Model.plain(modelData.role) + " · " + modelData.latency + " ms"
                    color: dim
                    font.family: fontFamily
                    font.pixelSize: Style.font.caption
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                  }
                }
              }
            }
            Text {
              width: parent.width
              visible: peers.length === 0
              horizontalAlignment: Text.AlignHCenter
              color: dim
              font.family: fontFamily
              text: "No peers"
              textFormat: Text.PlainText
            }
          }

          Text {
            width: parent.width
            visible: !showAuthSetup && activeTab === "server" && serverView === "networks"
            color: dim
            font.family: fontFamily
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
            text: controllerMetaLine
          }

          Column {
            id: serverNetworkList
            width: parent.width
            visible: !showAuthSetup && activeTab === "server" && serverView === "networks"
            spacing: Style.space(8)

            Repeater {
              model: controllerNetworks
              delegate: ControllerNetworkRow {
                width: column.width
                net: modelData
                rowIndex: index
                selected: index === controllerNetworkIndex
                onOpen: { controllerNetworkIndex = index; openControllerDetail(modelData) }
                onCopyId: copyText(modelData.id)
              }
            }

            Text {
              width: parent.width
              visible: controllerNetworks.length === 0
              horizontalAlignment: Text.AlignHCenter
              color: dim
              font.family: fontFamily
              text: hw && hw.controllerNetworksBusy ? "Loading controller networks…" : "No controller networks"
              textFormat: Text.PlainText
            }

            Text {
              width: parent.width
              visible: controllerNetworks.length > 0
              wrapMode: Text.WordWrap
              color: dim
              font.family: fontFamily
              font.pixelSize: Style.font.caption
              text: "↑↓ j/k rows · ←→ h/l actions · tab switch · n new · r refresh"
              textFormat: Text.PlainText
            }
          }

          Column {
            id: serverCreateCol
            width: parent.width
            visible: !showAuthSetup && activeTab === "server" && serverView === "create"
            spacing: Style.space(8)

            ConfigField {
              id: createNavName
              navHighlighted: root.isFormFieldHighlighted(0)
              label: "Network name"
              hint: "Label in controller UI and client network list"
              FormTextField {
                id: createNameField
                width: parent.width
                placeholderText: "my-network"
                font.family: fontFamily
                color: foreground
              }
            }
            ConfigField {
              id: createNavPoolStart
              navHighlighted: root.isFormFieldHighlighted(1)
              label: "Pool start"
              hint: "First IP controller can assign (e.g. 10.147.20.1)"
              FormTextField {
                id: createPoolStartField
                width: parent.width
                placeholderText: "10.147.20.1"
                font.family: fontFamily
                color: foreground
              }
            }
            ConfigField {
              id: createNavPoolEnd
              navHighlighted: root.isFormFieldHighlighted(2)
              label: "Pool end"
              hint: "Last IP in assignable range (e.g. 10.147.20.254)"
              FormTextField {
                id: createPoolEndField
                width: parent.width
                placeholderText: "10.147.20.254"
                font.family: fontFamily
                color: foreground
              }
            }
            ConfigField {
              id: createNavCidr
              navHighlighted: root.isFormFieldHighlighted(3)
              label: "Route CIDR"
              hint: "Subnet routed on this network (usually matches pool, e.g. 10.147.20.0/24)"
              FormTextField {
                id: createCidrField
                width: parent.width
                placeholderText: "10.147.20.0/24"
                font.family: fontFamily
                color: foreground
                onAccepted: root.submitNetworkCreate()
              }
            }
            ConfigField {
              id: createNavRoutes
              navHighlighted: root.isFormFieldHighlighted(4)
              label: "Extra routes"
              hint: "Optional. Comma-separated target;via pairs for additional routes"
              FormTextField {
                id: createRoutesField
                width: parent.width
                placeholderText: "10.0.0.0/8;10.147.20.1"
                font.family: fontFamily
                color: foreground
              }
            }
            ConfigField {
              id: createNavMtu
              navHighlighted: root.isFormFieldHighlighted(5)
              label: "MTU"
              hint: "Max packet size on virtual network in bytes (default 2800)"
              FormTextField {
                id: createMtuField
                width: parent.width
                placeholderText: "2800"
                font.family: fontFamily
                color: foreground
              }
            }
            ConfigField {
              id: createNavMulticast
              navHighlighted: root.isFormFieldHighlighted(6)
              label: "Multicast limit"
              hint: "Max multicast group members per node (default 32)"
              FormTextField {
                id: createMulticastField
                width: parent.width
                placeholderText: "32"
                font.family: fontFamily
                color: foreground
              }
            }
            ConfigField {
              id: createNavDnsDomain
              navHighlighted: root.isFormFieldHighlighted(7)
              label: "DNS domain"
              hint: "Search domain pushed to members (e.g. zt.local)"
              FormTextField {
                id: createDnsDomainField
                width: parent.width
                placeholderText: "zt.local"
                font.family: fontFamily
                color: foreground
              }
            }
            ConfigField {
              id: createNavDnsServers
              navHighlighted: root.isFormFieldHighlighted(8)
              label: "DNS servers"
              hint: "Comma-separated resolvers pushed to members"
              FormTextField {
                id: createDnsServersField
                width: parent.width
                placeholderText: "10.147.20.1"
                font.family: fontFamily
                color: foreground
              }
            }
            FormNavRow {
              id: createNavRules
              highlighted: root.isFormFieldHighlighted(9)
              ConfigField {
                width: parent.width
                label: "Flow rules"
                hint: "ZeroTier rule language (drop/accept; ethertype ipv4…) — or JSON array"
                Column {
                  width: parent.width
                  spacing: Style.space(4)
                  Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: Model.rulesPreview(createRulesField.text)
                    color: dim
                    font.family: fontFamily
                    font.pixelSize: Style.font.caption
                    textFormat: Text.PlainText
                  }
                  ActionChip {
                    label: "Edit rules…"
                    onActivated: root.openRulesEditor("create")
                  }
                }
              }
            }
            TextField {
              id: createRulesField
              visible: false
              width: 0
              height: 0
            }

            FormNavRow {
              id: createNavPrivate
              highlighted: root.isFormFieldHighlighted(10)
              Row {
                width: parent.width
                spacing: Style.space(8)
                Column {
                  width: parent.width - createPrivateSwitch.implicitWidth - parent.spacing
                  spacing: Style.space(2)
                  Text {
                    text: "Private network"
                    color: foreground
                    font.family: fontFamily
                    textFormat: Text.PlainText
                  }
                  Text {
                    wrapMode: Text.WordWrap
                    width: parent.width
                    text: "Require approval before nodes can join"
                    color: dim
                    font.family: fontFamily
                    font.pixelSize: Style.font.caption
                    textFormat: Text.PlainText
                  }
                }
                Switch { id: createPrivateSwitch; checked: true }
              }
            }
            FormNavRow {
              id: createNavBroadcast
              highlighted: root.isFormFieldHighlighted(11)
              Row {
                width: parent.width
                spacing: Style.space(8)
                Column {
                  width: parent.width - createBroadcastSwitch.implicitWidth - parent.spacing
                  spacing: Style.space(2)
                  Text {
                    text: "Ethernet broadcast"
                    color: foreground
                    font.family: fontFamily
                    textFormat: Text.PlainText
                  }
                  Text {
                    wrapMode: Text.WordWrap
                    width: parent.width
                    text: "Allow broadcast traffic on virtual Ethernet"
                    color: dim
                    font.family: fontFamily
                    font.pixelSize: Style.font.caption
                    textFormat: Text.PlainText
                  }
                }
                Switch { id: createBroadcastSwitch; checked: true }
              }
            }
            FormNavRow {
              id: createNavV4
              highlighted: root.isFormFieldHighlighted(12)
              Row {
                width: parent.width
                spacing: Style.space(8)
                Column {
                  width: parent.width - createV4ZTSwitch.implicitWidth - parent.spacing
                  spacing: Style.space(2)
                  Text {
                    text: "IPv4 auto-assign"
                    color: foreground
                    font.family: fontFamily
                    textFormat: Text.PlainText
                  }
                  Text {
                    wrapMode: Text.WordWrap
                    width: parent.width
                    text: "Controller assigns IPv4 from pool when member authorized"
                    color: dim
                    font.family: fontFamily
                    font.pixelSize: Style.font.caption
                    textFormat: Text.PlainText
                  }
                }
                Switch { id: createV4ZTSwitch; checked: true }
              }
            }
            FormNavRow {
              id: createNavV6Six
              highlighted: root.isFormFieldHighlighted(13)
              Row {
                width: parent.width
                spacing: Style.space(8)
                Text {
                  width: parent.width - createV6SixPlaneSwitch.implicitWidth - parent.spacing
                  anchors.verticalCenter: parent.verticalCenter
                  text: "IPv6 6plane"
                  color: foreground
                  font.family: fontFamily
                  textFormat: Text.PlainText
                }
                Switch { id: createV6SixPlaneSwitch }
              }
            }
            FormNavRow {
              id: createNavV6Rfc
              highlighted: root.isFormFieldHighlighted(14)
              Row {
                width: parent.width
                spacing: Style.space(8)
                Text {
                  width: parent.width - createV6RFC4193Switch.implicitWidth - parent.spacing
                  anchors.verticalCenter: parent.verticalCenter
                  text: "IPv6 RFC4193"
                  color: foreground
                  font.family: fontFamily
                  textFormat: Text.PlainText
                }
                Switch { id: createV6RFC4193Switch }
              }
            }
            FormNavRow {
              id: createNavV6Zt
              highlighted: root.isFormFieldHighlighted(15)
              Row {
                width: parent.width
                spacing: Style.space(8)
                Text {
                  width: parent.width - createV6ZTSwitch.implicitWidth - parent.spacing
                  anchors.verticalCenter: parent.verticalCenter
                  text: "IPv6 ZT assign"
                  color: foreground
                  font.family: fontFamily
                  textFormat: Text.PlainText
                }
                Switch { id: createV6ZTSwitch }
              }
            }

            Row {
              id: createFormFooter
              width: parent.width
              spacing: Style.space(8)
              Button {
                id: createSubmitBtn
                width: (parent.width - parent.spacing) / 2
                text: "Create"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                hasCursor: root.cursorActive && root.focusSection === "formFooter" && root.formActionIndex === 0
                onClicked: root.submitNetworkCreate()
              }
              Button {
                id: createBlankBtn
                width: (parent.width - parent.spacing) / 2
                text: "Blank"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                hasCursor: root.cursorActive && root.focusSection === "formFooter" && root.formActionIndex === 1
                onClicked: root.submitBlankNetworkCreate()
              }
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              color: dim
              font.family: fontFamily
              font.pixelSize: Style.font.caption
              text: "↑↓ fields/footer · ←→ create/blank · enter edit/toggle · esc exit field · b back"
              textFormat: Text.PlainText
            }
          }

          Column {
            id: serverRulesCol
            width: parent.width
            visible: !showAuthSetup && activeTab === "server" && serverView === "rules"
            spacing: Style.space(8)

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              color: dim
              font.family: fontFamily
              font.pixelSize: Style.font.caption
              textFormat: Text.PlainText
              text: "Rule language: drop/accept, ethertype, ipsrc, ztsrc, etc. Comments with #. Compiles to controller JSON on save. See docs.zerotier.com/rules"
            }

            Rectangle {
              width: parent.width
              radius: Style.cornerRadius
              color: root.cursorActive && root.focusSection === "editor"
                ? hoverFill
                : Qt.rgba(foreground.r, foreground.g, foreground.b, 0.04)
              implicitHeight: rulesEditorBox.height + Style.space(16)

              Flickable {
                id: rulesEditorBox
                anchors.centerIn: parent
                width: parent.width - Style.space(16)
                height: Math.min(Style.space(360), Math.max(Style.space(200), rulesEditorField.contentHeight + Style.space(16)))
                contentHeight: rulesEditorField.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
                interactive: contentHeight > height
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                TextEdit {
                  id: rulesEditorField
                  width: parent.width
                  wrapMode: TextEdit.Wrap
                  text: rulesEditorText
                  font.family: fontFamily
                  font.pixelSize: Style.font.bodySmall
                  color: foreground
                  selectByMouse: true
                  padding: Style.space(8)
                  onTextChanged: rulesEditorText = text
                  Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
                      root.saveRulesEditor()
                      event.accepted = true
                      return
                    }
                    if (event.key === Qt.Key_Escape) {
                      root.cancelRulesEditor()
                      event.accepted = true
                    }
                  }
                }
              }
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              color: dim
              font.family: fontFamily
              font.pixelSize: Style.font.caption
              text: "↑↓ back/editor/footer · enter edit/save · s save · b/esc back · ctrl+s save while typing"
              textFormat: Text.PlainText
            }
          }

          Column {
            width: parent.width
            visible: !showAuthSetup && activeTab === "server" && serverView === "detail" && selectedControllerNetwork
            spacing: Style.space(8)

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              color: dim
              font.family: fontFamily
              font.pixelSize: Style.font.caption
              textFormat: Text.PlainText
              text: Model.controllerNetworkDetailText(selectedControllerNetwork)
            }

            Flow {
              id: serverDetailChips
              width: parent.width
              spacing: Style.space(6)
              ActionChip {
                label: "Copy ID"
                chipActive: root.cursorActive && root.focusSection === "detailChips" && root.chipIndex === 0
                onActivated: copyText(selectedControllerNetwork.id)
              }
              ActionChip {
                label: "Members"
                chipActive: root.cursorActive && root.focusSection === "detailChips" && root.chipIndex === 1
                onActivated: openControllerMembers()
              }
              ActionChip {
                label: "Edit"
                chipActive: root.cursorActive && root.focusSection === "detailChips" && root.chipIndex === 2
                onActivated: openControllerEdit()
              }
              ActionChip {
                label: "Delete"
                chipActive: root.cursorActive && root.focusSection === "detailChips" && root.chipIndex === 3
                onActivated: pendingDeleteNetwork = selectedControllerNetwork
              }
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              color: dim
              font.family: fontFamily
              font.pixelSize: Style.font.caption
              text: "↑↓ back/chips · ←→ actions · enter open · b back"
              textFormat: Text.PlainText
            }
          }

          Column {
            width: parent.width
            visible: !showAuthSetup && activeTab === "server" && serverView === "edit" && selectedControllerNetwork
            spacing: Style.space(8)

            ConfigField {
              id: editNavName
              navHighlighted: root.isFormFieldHighlighted(0)
              label: "Network name"
              FormTextField {
                id: editNameField
                width: parent.width
                text: editNetName
                placeholderText: "my-network"
                font.family: fontFamily
                color: foreground
                onTextChanged: editNetName = text
              }
            }
            ConfigField {
              id: editNavPoolStart
              navHighlighted: root.isFormFieldHighlighted(1)
              label: "Pool start"
              hint: "First assignable IP in range"
              FormTextField {
                id: editPoolStartField
                width: parent.width
                text: editPoolStart
                placeholderText: "10.147.20.1"
                font.family: fontFamily
                color: foreground
                onTextChanged: editPoolStart = text
              }
            }
            ConfigField {
              id: editNavPoolEnd
              navHighlighted: root.isFormFieldHighlighted(2)
              label: "Pool end"
              hint: "Last assignable IP in range"
              FormTextField {
                id: editPoolEndField
                width: parent.width
                text: editPoolEnd
                placeholderText: "10.147.20.254"
                font.family: fontFamily
                color: foreground
                onTextChanged: editPoolEnd = text
              }
            }
            ConfigField {
              id: editNavMtu
              navHighlighted: root.isFormFieldHighlighted(3)
              label: "MTU"
              hint: "Max packet size on virtual network in bytes"
              FormTextField {
                id: editMtuField
                width: parent.width
                text: editMtu
                placeholderText: "2800"
                font.family: fontFamily
                color: foreground
                onTextChanged: editMtu = text
              }
            }
            ConfigField {
              id: editNavMulticast
              navHighlighted: root.isFormFieldHighlighted(4)
              label: "Multicast limit"
              hint: "Max multicast group members per node"
              FormTextField {
                id: editMulticastField
                width: parent.width
                text: editMulticastLimit
                placeholderText: "32"
                font.family: fontFamily
                color: foreground
                onTextChanged: editMulticastLimit = text
              }
            }
            ConfigField {
              id: editNavRoutes
              navHighlighted: root.isFormFieldHighlighted(5)
              label: "Extra routes"
              hint: "Comma-separated target;via pairs for additional routes"
              FormTextField {
                id: editRoutesField
                width: parent.width
                text: editRoutes
                placeholderText: "10.0.0.0/8;10.147.20.1"
                font.family: fontFamily
                color: foreground
                onTextChanged: editRoutes = text
              }
            }
            ConfigField {
              id: editNavDnsDomain
              navHighlighted: root.isFormFieldHighlighted(6)
              label: "DNS domain"
              hint: "Search domain pushed to members"
              FormTextField {
                id: editDnsDomainField
                width: parent.width
                text: editDnsDomain
                placeholderText: "zt.local"
                font.family: fontFamily
                color: foreground
                onTextChanged: editDnsDomain = text
              }
            }
            ConfigField {
              id: editNavDnsServers
              navHighlighted: root.isFormFieldHighlighted(7)
              label: "DNS servers"
              hint: "Comma-separated resolvers pushed to members"
              FormTextField {
                id: editDnsServersField
                width: parent.width
                text: editDnsServers
                placeholderText: "10.147.20.1"
                font.family: fontFamily
                color: foreground
                onTextChanged: editDnsServers = text
              }
            }
            FormNavRow {
              id: editNavRules
              highlighted: root.isFormFieldHighlighted(8)
              ConfigField {
                width: parent.width
                label: "Flow rules"
                hint: "ZeroTier rule language — or JSON array; open editor for multiline"
                Column {
                  width: parent.width
                  spacing: Style.space(4)
                  Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: Model.rulesPreview(editRules)
                    color: dim
                    font.family: fontFamily
                    font.pixelSize: Style.font.caption
                    textFormat: Text.PlainText
                  }
                  ActionChip {
                    label: "Edit rules…"
                    onActivated: root.openRulesEditor("edit")
                  }
                }
              }
            }

            FormNavRow {
              id: editNavPrivate
              highlighted: root.isFormFieldHighlighted(9)
              Row {
                width: parent.width
                spacing: Style.space(8)
                Text {
                  width: parent.width - editPrivateSwitch.implicitWidth - parent.spacing
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Private"
                  color: foreground
                  font.family: fontFamily
                  textFormat: Text.PlainText
                }
                Switch {
                  id: editPrivateSwitch
                  anchors.verticalCenter: parent.verticalCenter
                  checked: editPrivate
                  onToggled: editPrivate = checked
                }
              }
            }

            FormNavRow {
              id: editNavBroadcast
              highlighted: root.isFormFieldHighlighted(10)
              Row {
                width: parent.width
                spacing: Style.space(8)
                Text {
                  width: parent.width - editBroadcastSwitch.implicitWidth - parent.spacing
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Broadcast"
                  color: foreground
                  font.family: fontFamily
                  textFormat: Text.PlainText
                }
                Switch {
                  id: editBroadcastSwitch
                  anchors.verticalCenter: parent.verticalCenter
                  checked: editBroadcast
                  onToggled: editBroadcast = checked
                }
              }
            }

            FormNavRow {
              id: editNavV4
              highlighted: root.isFormFieldHighlighted(11)
              Row {
                width: parent.width
                spacing: Style.space(8)
                Text {
                  width: parent.width - editV4ZTSwitch.implicitWidth - parent.spacing
                  anchors.verticalCenter: parent.verticalCenter
                  text: "IPv4 ZT assign"
                  color: foreground
                  font.family: fontFamily
                  textFormat: Text.PlainText
                }
                Switch {
                  id: editV4ZTSwitch
                  anchors.verticalCenter: parent.verticalCenter
                  checked: editV4ZT
                  onToggled: editV4ZT = checked
                }
              }
            }

            FormNavRow {
              id: editNavV6Six
              highlighted: root.isFormFieldHighlighted(12)
              Row {
                width: parent.width
                spacing: Style.space(8)
                Text {
                  width: parent.width - editV6SixPlaneSwitch.implicitWidth - parent.spacing
                  anchors.verticalCenter: parent.verticalCenter
                  text: "IPv6 6plane"
                  color: foreground
                  font.family: fontFamily
                  textFormat: Text.PlainText
                }
                Switch {
                  id: editV6SixPlaneSwitch
                  anchors.verticalCenter: parent.verticalCenter
                  checked: editV6SixPlane
                  onToggled: editV6SixPlane = checked
                }
              }
            }

            FormNavRow {
              id: editNavV6Rfc
              highlighted: root.isFormFieldHighlighted(13)
              Row {
                width: parent.width
                spacing: Style.space(8)
                Text {
                  width: parent.width - editV6RFC4193Switch.implicitWidth - parent.spacing
                  anchors.verticalCenter: parent.verticalCenter
                  text: "IPv6 RFC4193"
                  color: foreground
                  font.family: fontFamily
                  textFormat: Text.PlainText
                }
                Switch {
                  id: editV6RFC4193Switch
                  anchors.verticalCenter: parent.verticalCenter
                  checked: editV6RFC4193
                  onToggled: editV6RFC4193 = checked
                }
              }
            }

            FormNavRow {
              id: editNavV6Zt
              highlighted: root.isFormFieldHighlighted(14)
              Row {
                width: parent.width
                spacing: Style.space(8)
                Text {
                  width: parent.width - editV6ZTSwitch.implicitWidth - parent.spacing
                  anchors.verticalCenter: parent.verticalCenter
                  text: "IPv6 ZT assign"
                  color: foreground
                  font.family: fontFamily
                  textFormat: Text.PlainText
                }
                Switch {
                  id: editV6ZTSwitch
                  anchors.verticalCenter: parent.verticalCenter
                  checked: editV6ZT
                  onToggled: editV6ZT = checked
                }
              }
            }

            Button {
              id: editSaveBtn
              width: parent.width
              text: "Save changes"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              hasCursor: root.cursorActive && root.focusSection === "formFooter" && serverView === "edit"
              onClicked: submitNetworkUpdate()
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              color: dim
              font.family: fontFamily
              font.pixelSize: Style.font.caption
              text: "↑↓ fields/save · enter edit/toggle/save · esc exit field · b back"
              textFormat: Text.PlainText
            }
          }

          Column {
            id: serverMemberList
            width: parent.width
            visible: !showAuthSetup && activeTab === "server" && serverView === "members"
            spacing: Style.space(6)

            Repeater {
              model: controllerMembers
              delegate: ControllerMemberRow {
                width: column.width
                member: modelData
                rowIndex: index
                onOpen: openMemberDetail(modelData)
                onCopyId: copyText(modelData.address)
                onAuthorize: {
                  if (hw && selectedControllerNetwork)
                    hw.authorizeControllerMember(
                      selectedControllerNetwork.id,
                      modelData.address,
                      selectedControllerNetwork,
                      controllerMembers,
                      function(ok) { if (ok) hw.refreshControllerMembers(selectedControllerNetwork.id) }
                    )
                }
              }
            }

            Text {
              width: parent.width
              visible: controllerMembers.length === 0
              horizontalAlignment: Text.AlignHCenter
              color: dim
              font.family: fontFamily
              text: hw && hw.controllerMembersBusy ? "Loading members…" : "No members"
              textFormat: Text.PlainText
            }

            Text {
              width: parent.width
              visible: controllerMembers.length > 0
              wrapMode: Text.WordWrap
              color: dim
              font.family: fontFamily
              font.pixelSize: Style.font.caption
              text: "↑↓ j/k move · enter detail · r refresh"
              textFormat: Text.PlainText
            }
          }

          Column {
            width: parent.width
            visible: !showAuthSetup && activeTab === "server" && serverView === "memberDetail" && selectedControllerMember
            spacing: Style.space(8)

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              color: dim
              font.family: fontFamily
              font.pixelSize: Style.font.caption
              textFormat: Text.PlainText
              text: Model.plain(selectedControllerMember.address) + "\n"
                + "Version " + Model.plain(selectedControllerMember.version)
            }

            ConfigField {
              id: memberNavName
              navHighlighted: root.isFormFieldHighlighted(0)
              label: "Member name"
              FormTextField {
                id: memberNameInput
                width: parent.width
                text: memberNameField
                placeholderText: "Member name"
                font.family: fontFamily
                color: foreground
                onTextChanged: memberNameField = text
                onAccepted: updateMember({ name: memberNameField })
              }
            }

            Repeater {
              id: memberToggleNav
              model: [
                { key: "authorized", label: "Authorized", value: selectedControllerMember ? selectedControllerMember.authorized : false },
                { key: "activeBridge", label: "Active bridge", value: selectedControllerMember ? selectedControllerMember.activeBridge : false },
                { key: "noAutoAssignIps", label: "No auto IPs", value: selectedControllerMember ? selectedControllerMember.noAutoAssignIps : false }
              ]
              delegate: FormNavRow {
                highlighted: root.isFormFieldHighlighted(index + 1)
                Row {
                  width: parent.width
                  spacing: Style.space(8)
                  Text {
                    width: parent.width - memToggle.implicitWidth - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.label
                    color: foreground
                    font.family: fontFamily
                    textFormat: Text.PlainText
                  }
                  Switch {
                    id: memToggle
                    anchors.verticalCenter: parent.verticalCenter
                    checked: modelData.value
                    enabled: selectedControllerMember !== null
                    onToggled: {
                      var patch = {}
                      patch[modelData.key] = checked
                      updateMember(patch)
                    }
                  }
                }
              }
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              color: dim
              font.family: fontFamily
              font.pixelSize: Style.font.caption
              textFormat: Text.PlainText
              text: "IPs " + Model.joinAddresses(selectedControllerMember.ipAssignments)
            }

            FormNavRow {
              id: memberNavIpRow
              highlighted: root.isFormFieldHighlighted(4)
              Row {
                width: parent.width
                spacing: Style.space(8)
                FormTextField {
                  id: memberIpInput
                  width: parent.width - addIpBtn.implicitWidth - parent.spacing
                  text: memberIpField
                  placeholderText: "Add IP (e.g. 10.147.20.5)"
                  font.family: fontFamily
                  color: foreground
                  onTextChanged: memberIpField = text
                  onAccepted: submitAddMemberIp()
                }
                Button {
                  id: addIpBtn
                  text: "Add"
                  bordered: true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  verticalPadding: Style.spacing.controlPaddingY
                  onClicked: submitAddMemberIp()
                }
              }
            }

            Flow {
              width: parent.width
              spacing: Style.space(6)
              Repeater {
                id: memberIpChipNav
                model: selectedControllerMember ? selectedControllerMember.ipAssignments : []
                delegate: FormNavRow {
                  highlighted: root.isFormFieldHighlighted(index + 5)
                  ActionChip {
                    label: "− " + Model.plain(modelData)
                    onActivated: removeMemberIp(modelData)
                  }
                }
              }
            }

            Flow {
              id: memberDetailChips
              width: parent.width
              spacing: Style.space(6)
              ActionChip {
                label: "Save name"
                chipActive: root.cursorActive && root.focusSection === "detailChips" && root.chipIndex === 0
                onActivated: updateMember({ name: memberNameField })
              }
              ActionChip {
                label: "Copy node ID"
                chipActive: root.cursorActive && root.focusSection === "detailChips" && root.chipIndex === 1
                onActivated: copyText(selectedControllerMember ? selectedControllerMember.address : "")
              }
              ActionChip {
                label: "Remove member"
                chipActive: root.cursorActive && root.focusSection === "detailChips" && root.chipIndex === 2
                onActivated: pendingDeleteMember = selectedControllerMember
              }
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              color: dim
              font.family: fontFamily
              font.pixelSize: Style.font.caption
              text: "↑↓ fields/chips · enter edit/toggle/remove · esc exit field · b back"
              textFormat: Text.PlainText
            }
          }
        }
      }

      Item {
        id: footerBar
        z: 2
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        visible: showFooter
        height: visible ? footerCol.implicitHeight : 0

        Column {
          id: footerCol
          width: parent.width
          spacing: Style.space(8)

          Column {
            width: parent.width
            visible: serverMemberAddOpen && showServerMembersFooter
            spacing: Style.space(6)

            TextField {
              id: addMemberInput
              width: parent.width
              text: addMemberField
              placeholderText: "10-char node ID"
              maximumLength: 10
              font.family: fontFamily
              color: foreground
              onTextChanged: addMemberField = text
              onAccepted: root.submitAddMember()
            }

            Button {
              width: parent.width
              text: "Authorize member"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.submitAddMember()
            }
          }

          Column {
            width: parent.width
            visible: joinOpen && showClientFooter
            spacing: Style.space(6)

            TextField {
              id: joinField
              width: parent.width
              placeholderText: "16-hex network ID"
              maximumLength: 16
              font.family: fontFamily
              color: foreground
              onAccepted: root.submitJoin()
            }

            Button {
              width: parent.width
              text: "Join network"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.submitJoin()
            }
          }

          Row {
            id: clientFooterRow
            width: parent.width
            visible: showClientFooter
            spacing: Style.space(8)

            Button {
              id: peersBtn
              text: "Peers · " + peers.length
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              selected: clientView === "peers"
              hasCursor: root.cursorActive && root.focusSection === "footer" && root.footerIndex === 0 && showClientFooter
              onClicked: {
                clientView = "peers"
                joinOpen = false
              }
            }

            Item {
              width: Math.max(0, parent.width - peersBtn.implicitWidth - clientJoinBtn.implicitWidth - parent.spacing)
              height: 1
            }

            PanelActionButton {
              id: clientJoinBtn
              iconText: joinOpen ? "󰅖" : "󰐕"
              tooltipText: joinOpen ? "Cancel join" : "Join network"
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusSection === "footer" && root.footerIndex === 1 && showClientFooter
              onClicked: joinOpen = !joinOpen
            }
          }

          Row {
            id: serverFooterRow
            width: parent.width
            visible: showServerFooter
            spacing: Style.space(8)

            Text {
              text: controllerNetworks.length + " network(s)"
              color: dim
              font.family: fontFamily
              font.pixelSize: Style.font.caption
              textFormat: Text.PlainText
            }

            Item {
              width: Math.max(0, parent.width - parent.children[0].implicitWidth - serverRefreshBtn.implicitWidth - serverCreateBtn.implicitWidth - parent.spacing * 2)
              height: 1
            }

            PanelActionButton {
              id: serverRefreshBtn
              iconText: "󰑐"
              tooltipText: "Refresh controller networks"
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusSection === "footer" && root.footerIndex === 0 && showServerFooter
              onClicked: { if (hw) hw.refreshControllerNetworks() }
            }

            PanelActionButton {
              id: serverCreateBtn
              iconText: "󰐕"
              tooltipText: "Create network"
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusSection === "footer" && root.footerIndex === 1 && showServerFooter
              onClicked: root.openServerCreate()
            }
          }

          Row {
            id: serverMembersFooterRow
            width: parent.width
            visible: showServerMembersFooter
            spacing: Style.space(8)

            Text {
              text: controllerMembers.length + " member(s)"
              color: dim
              font.family: fontFamily
              font.pixelSize: Style.font.caption
              textFormat: Text.PlainText
            }

            Item {
              width: Math.max(0, parent.width - parent.children[0].implicitWidth - membersRefreshBtn.implicitWidth - membersAddBtn.implicitWidth - parent.spacing * 2)
              height: 1
            }

            PanelActionButton {
              id: membersRefreshBtn
              iconText: "󰑐"
              tooltipText: "Refresh members"
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusSection === "footer" && root.footerIndex === 0 && showServerMembersFooter
              onClicked: {
                if (hw && selectedControllerNetwork)
                  hw.refreshControllerMembers(selectedControllerNetwork.id)
              }
            }

            PanelActionButton {
              id: membersAddBtn
              iconText: serverMemberAddOpen ? "󰅖" : "󰐕"
              tooltipText: serverMemberAddOpen ? "Cancel add" : "Authorize member"
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusSection === "footer" && root.footerIndex === 1 && showServerMembersFooter
              onClicked: serverMemberAddOpen = !serverMemberAddOpen
            }
          }

          Row {
            id: rulesFooterRow
            width: parent.width
            visible: showRulesFooter
            spacing: Style.space(8)

            Button {
              id: rulesSaveBtn
              width: (parent.width - parent.spacing) / 2
              text: "Save rules"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              hasCursor: root.cursorActive && root.focusSection === "footer" && root.footerIndex === 0 && showRulesFooter
              onClicked: root.saveRulesEditor()
            }

            Button {
              id: rulesCancelBtn
              width: (parent.width - parent.spacing) / 2
              text: "Cancel"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              hasCursor: root.cursorActive && root.focusSection === "footer" && root.footerIndex === 1 && showRulesFooter
              onClicked: root.cancelRulesEditor()
            }
          }
        }
      }
    }
  }

    ConfirmDialog {
      id: leaveConfirm
      anchors.fill: parent
      opened: pendingLeave !== null
      message: leaveMessage(pendingLeave)
      confirmText: "Leave"
      fontFamily: root.fontFamily
      foreground: root.foreground
      onOpenedChanged: if (opened) selectedIndex = 1
      onConfirmed: {
        if (hw && pendingLeave) {
          var leaveId = pendingLeave.id
          pendingLeave = null
          hw.leaveNetwork(leaveId, function(ok) {
            if (ok) finishClientLeaveNav()
          })
        } else {
          pendingLeave = null
        }
      }
      onCanceled: pendingLeave = null
    }

    ConfirmDialog {
      id: deleteNetworkConfirm
      anchors.fill: parent
      opened: pendingDeleteNetwork !== null
      message: pendingDeleteNetwork
        ? "Delete network " + Model.plain(pendingDeleteNetwork.id) + "?\n"
          + Model.controllerNetworkLabel(pendingDeleteNetwork)
        : ""
      confirmText: "Delete"
      fontFamily: root.fontFamily
      foreground: root.foreground
      onOpenedChanged: if (opened) selectedIndex = 1
      onConfirmed: {
        if (hw && pendingDeleteNetwork) {
          var nwid = pendingDeleteNetwork.id
          pendingDeleteNetwork = null
          hw.deleteControllerNetwork(nwid, function(ok) {
            if (ok) finishServerDeleteNav()
          })
        } else {
          pendingDeleteNetwork = null
        }
      }
      onCanceled: pendingDeleteNetwork = null
    }

    ConfirmDialog {
      id: deleteMemberConfirm
      anchors.fill: parent
      opened: pendingDeleteMember !== null
      message: pendingDeleteMember
        ? "Remove member " + Model.plain(pendingDeleteMember.address) + "?\n"
          + Model.memberLabel(pendingDeleteMember)
        : ""
      confirmText: "Remove"
      fontFamily: root.fontFamily
      foreground: root.foreground
      onOpenedChanged: if (opened) selectedIndex = 1
      onConfirmed: {
        if (hw && pendingDeleteMember && selectedControllerNetwork) {
          var node = pendingDeleteMember.address
          var nwid = selectedControllerNetwork.id
          pendingDeleteMember = null
          hw.deleteControllerMember(nwid, node, function(ok) {
            if (ok) {
              serverView = "members"
              selectedControllerMember = null
              focusSection = "list"
              chipIndex = 0
              clampNavIndices()
              restorePanelFocus()
            }
          })
        } else {
          pendingDeleteMember = null
        }
      }
      onCanceled: pendingDeleteMember = null
    }

    Item {
      id: confirmKeyFocus
      anchors.fill: parent
      z: 200
      enabled: root.confirmOpen
      visible: root.confirmOpen
      focus: root.confirmOpen
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (root.handleConfirmKey(event)) event.accepted = true
      }
    }
  }

  component NetworkRow: CursorSurface {
    id: row
    property var net
    property int rowIndex: 0
    property bool selected: false
    signal open()
    signal toggleConnection()
    signal copyIp()

    width: parent.width
    hasCursor: root.cursorActive && (root.focusSection === "list" || root.focusSection === "rowChips")
      && root.activeTab === "client" && root.clientView === "networks"
      && root.networkIndex === rowIndex
    current: selected
    foreground: root.foreground
    implicitHeight: inner.implicitHeight + Style.space(16)

    Column {
      id: inner
      width: parent.width - Style.space(16)
      anchors.centerIn: parent
      spacing: Style.space(4)

      Text {
        width: parent.width
        elide: Text.ElideRight
        text: Model.networkLabel(net)
        color: foreground
        font.family: fontFamily
        font.pixelSize: Style.font.body
        textFormat: Text.PlainText
      }
      Text {
        width: parent.width
        elide: Text.ElideRight
        text: Model.plain(net.status)
          + " · " + Model.clientNetworkConnectionSummary(net)
          + " · " + Model.joinAddresses(net.assignedAddresses)
        color: dim
        font.family: fontFamily
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }
      Text {
        width: parent.width
        elide: Text.ElideRight
        text: Model.plain(net.id)
        color: dim
        font.family: fontFamily
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }
      Flow {
        width: parent.width
        spacing: Style.space(6)
        ActionChip {
          label: "Detail"
          chipActive: root.cursorActive && root.focusSection === "rowChips"
            && root.networkIndex === rowIndex && root.chipIndex === 0
          onActivated: row.open()
        }
        ActionChip {
          label: "Copy IP"
          chipActive: root.cursorActive && root.focusSection === "rowChips"
            && root.networkIndex === rowIndex && root.chipIndex === 1
          onActivated: row.copyIp()
        }
        ActionChip {
          label: Model.clientNetworkConnectionLabel(net)
          chipActive: root.cursorActive && root.focusSection === "rowChips"
            && root.networkIndex === rowIndex && root.chipIndex === 2
          onActivated: row.toggleConnection()
        }
      }
    }

    MouseArea {
      z: -1
      anchors.fill: parent
      hoverEnabled: true
      onContainsMouseChanged: if (containsMouse) root.focusListRow(rowIndex)
      onClicked: row.open()
    }
  }

  component ControllerNetworkRow: CursorSurface {
    id: crow
    property var net
    property int rowIndex: 0
    property bool selected: false
    signal open()
    signal copyId()

    width: parent.width
    hasCursor: root.cursorActive && (root.focusSection === "list" || root.focusSection === "rowChips")
      && root.activeTab === "server" && root.serverView === "networks"
      && root.controllerNetworkIndex === rowIndex
    current: selected
    foreground: root.foreground
    implicitHeight: inner.implicitHeight + Style.space(16)

    Column {
      id: inner
      width: parent.width - Style.space(16)
      anchors.centerIn: parent
      spacing: Style.space(4)

      Text {
        width: parent.width
        elide: Text.ElideRight
        text: Model.controllerNetworkLabel(net)
        color: foreground
        font.family: fontFamily
        font.pixelSize: Style.font.body
        textFormat: Text.PlainText
      }
      Text {
        width: parent.width
        elide: Text.ElideRight
        text: (net.private ? "Private" : "Public")
          + " · Pool " + Model.controllerPoolSummary(net)
        color: dim
        font.family: fontFamily
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }
      Text {
        width: parent.width
        elide: Text.ElideRight
        text: Model.plain(net.id)
        color: dim
        font.family: fontFamily
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }
      Flow {
        width: parent.width
        spacing: Style.space(6)
        ActionChip {
          label: "Detail"
          chipActive: root.cursorActive && root.focusSection === "rowChips"
            && root.controllerNetworkIndex === rowIndex && root.chipIndex === 0
          onActivated: crow.open()
        }
        ActionChip {
          label: "Copy ID"
          chipActive: root.cursorActive && root.focusSection === "rowChips"
            && root.controllerNetworkIndex === rowIndex && root.chipIndex === 1
          onActivated: crow.copyId()
        }
      }
    }

    MouseArea {
      z: -1
      anchors.fill: parent
      hoverEnabled: true
      onContainsMouseChanged: if (containsMouse) root.focusListRow(rowIndex)
      onClicked: crow.open()
    }
  }

  component ControllerMemberRow: CursorSurface {
    id: mrow
    property var member
    property int rowIndex: 0
    signal open()
    signal copyId()
    signal authorize()

    width: parent.width
    hasCursor: root.cursorActive && (root.focusSection === "list" || root.focusSection === "rowChips")
      && root.activeTab === "server" && root.serverView === "members"
      && root.memberIndex === rowIndex
    foreground: root.foreground
    implicitHeight: inner.implicitHeight + Style.space(12)

    Column {
      id: inner
      width: parent.width - Style.space(16)
      anchors.centerIn: parent
      spacing: Style.space(2)

      Text {
        width: parent.width
        elide: Text.ElideRight
        text: Model.memberLabel(member)
        color: foreground
        font.family: fontFamily
        font.pixelSize: Style.font.body
        textFormat: Text.PlainText
      }
      Text {
        width: parent.width
        elide: Text.ElideRight
        text: Model.plain(member.address)
          + " · " + (member.authorized ? "authorized" : "pending")
          + " · " + Model.joinAddresses(member.ipAssignments)
        color: dim
        font.family: fontFamily
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }
      Flow {
        width: parent.width
        spacing: Style.space(6)
        ActionChip {
          label: "Detail"
          chipActive: root.cursorActive && root.focusSection === "rowChips"
            && root.memberIndex === rowIndex && root.chipIndex === 0
          onActivated: mrow.open()
        }
        ActionChip {
          label: "Copy ID"
          chipActive: root.cursorActive && root.focusSection === "rowChips"
            && root.memberIndex === rowIndex && root.chipIndex === 1
          onActivated: mrow.copyId()
        }
        ActionChip {
          visible: member && !member.authorized
          label: "Authorize"
          chipActive: root.cursorActive && root.focusSection === "rowChips"
            && root.memberIndex === rowIndex && root.chipIndex === 2
          onActivated: mrow.authorize()
        }
      }
    }

    MouseArea {
      z: -1
      anchors.fill: parent
      hoverEnabled: true
      onContainsMouseChanged: if (containsMouse) root.focusListRow(rowIndex)
      onClicked: mrow.open()
    }
  }
}
