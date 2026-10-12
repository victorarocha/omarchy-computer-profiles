.pragma library

function plain(value) {
  return String(value === undefined || value === null ? "" : value)
    .replace(/[\u0000-\u001f\u007f-\u009f]/g, " ")
    .replace(/[\u202a-\u202e\u2066-\u2069]/g, "")
    .replace(/</g, "\u2039")
    .replace(/>/g, "\u203a")
}

function wrapEnvelope(payload) {
  if (!payload || typeof payload !== "object")
    return { ok: false, error: "invalid response", needsAuth: false, body: null }
  var body = payload["data"]
  if (body === undefined) body = payload["body"]
  return {
    ok: payload["ok"] === true,
    error: payload["error"] ? String(payload["error"]) : "",
    needsAuth: payload["needsAuth"] === true,
    body: body === undefined ? null : body
  }
}

function parseEnvelope(text) {
  var raw = String(text === undefined || text === null ? "" : text).trim()
  if (raw === "") return { ok: false, error: "empty backend response", needsAuth: false, body: null }
  try {
    return wrapEnvelope(JSON.parse(raw))
  } catch (e) {
    var line = raw.split("\n")[0].trim()
    if (line !== raw) {
      try {
        return wrapEnvelope(JSON.parse(line))
      } catch (e2) {}
    }
    return { ok: false, error: "invalid JSON from backend", needsAuth: false, body: null }
  }
}

function snapshotState(text) {
  var env = parseEnvelope(text)
  if (!env.ok)
    return {
      ok: false, error: env.error || "request failed", needsAuth: env.needsAuth === true,
      hasToken: false, tokenSource: "", serviceReachable: false,
      address: "", online: false, version: "",
      controller: false, networks: [], peers: []
    }
  var d = env.body || {}
  var au = d["auth"] || {}
  var st = d["status"]
  var ctrl = d["controller"] || {}
  return {
    ok: true,
    error: "",
    needsAuth: au["hasToken"] !== true,
    hasToken: au["hasToken"] === true,
    tokenSource: String(au["source"] || ""),
    serviceReachable: au["serviceReachable"] === true,
    address: st ? String(st["address"] || "") : "",
    online: st && (st["online"] === true || st["online"] === 1),
    version: st ? String(st["version"] || "") : "",
    networks: normalizeNetworks(d["networks"]),
    controller: ctrl["controller"] === true,
    apiVersion: ctrl["apiVersion"],
    peers: normalizePeers(d["peers"])
  }
}

function networkLabel(net) {
  if (!net) return "Unknown"
  var name = plain(net.name)
  if (name !== "") return name
  return plain(net.id) || "Unknown"
}

function joinAddresses(addrs) {
  if (!addrs || !addrs.length) return "—"
  var out = []
  for (var i = 0; i < addrs.length; i++) out.push(plain(addrs[i]))
  return out.join(", ")
}

function statusTone(status) {
  var s = String(status || "").toUpperCase()
  if (s === "OK") return "ok"
  if (s === "ACCESS_DENIED") return "warn"
  if (s === "NOT_FOUND") return "warn"
  return "dim"
}

function isClientNetworkConnected(net) {
  return net && net.allowManaged === true
}

function clientNetworkConnectionLabel(net) {
  return isClientNetworkConnected(net) ? "Disconnect" : "Connect"
}

function clientNetworkConnectionSummary(net) {
  if (!net) return ""
  return isClientNetworkConnected(net) ? "connected" : "disconnected"
}

function rulesPreview(text) {
  var t = String(text === undefined || text === null ? "" : text).trim()
  if (t === "" || t === "[]") return "No custom rules (controller accepts all traffic)"
  if (t.startsWith("[")) {
    if (t === '[{"type":"ACTION_ACCEPT"}]') return "Accept all traffic (default)"
    var oneLine = t.replace(/\s+/g, " ")
    if (oneLine.length > 72) return oneLine.slice(0, 72) + "…"
    return oneLine
  }
  var lines = t.split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line === "" || line.startsWith("#")) continue
    if (line.length > 72) return line.slice(0, 72) + "…"
    return line + " …"
  }
  return "Custom flow rules"
}

function defaultFlowRulesText() {
  return (
    "# Allow only IPv4, IPv4 ARP, and IPv6 Ethernet frames.\n"
    + "drop\n"
    + "  not ethertype ipv4\n"
    + "  and not ethertype arp\n"
    + "  and not ethertype ipv6\n"
    + ";\n"
    + "# Uncomment to block manual IPs (prevents spoofing):\n"
    + "#drop\n"
    + "#  not chr ipauth\n"
    + "#;\n"
    + "accept;"
  )
}

function formatRulesEditorText(text) {
  var t = String(text === undefined || text === null ? "" : text).trim()
  if (!t.startsWith("[")) return t
  try {
    return JSON.stringify(JSON.parse(t), null, 2)
  } catch (e) {
    return t
  }
}

function isAcceptOnlyRulesJson(text) {
  var t = String(text === undefined || text === null ? "" : text).trim()
  if (t === "" || t === "[]") return true
  try {
    var rules = JSON.parse(t)
    if (!rules || rules.length !== 1) return false
    return plain(rules[0].type) === "ACTION_ACCEPT"
  } catch (e) {
    return false
  }
}

function rulesEditorTextFromNetwork(net) {
  if (!net) return defaultFlowRulesText()
  var json = rulesToJson(net.rules)
  if (isAcceptOnlyRulesJson(json)) return defaultFlowRulesText()
  return formatRulesEditorText(json)
}

function shortNodeId(address) {
  var a = plain(address)
  if (a.length <= 10) return a
  return a.slice(0, 5) + "…" + a.slice(-4)
}

function sortNetworks(networks) {
  var list = (networks || []).slice()
  list.sort(function(a, b) {
    var an = networkLabel(a).toLowerCase()
    var bn = networkLabel(b).toLowerCase()
    return an < bn ? -1 : an > bn ? 1 : 0
  })
  return list
}

function asArray(raw) {
  var out = []
  if (raw === undefined || raw === null) return out
  var len = raw.length
  if (typeof len === "number" && len >= 0) {
    for (var i = 0; i < len; i++) out.push(raw[i])
    return out
  }
  for (var j = 0; j < 8192; j++) {
    if (raw[j] === undefined) break
    out.push(raw[j])
  }
  return out
}

function normalizeNetwork(net) {
  if (!net) return null
  var id = plain(net.id)
  if (id === "") id = plain(net.nwid)
  return {
    id: id,
    name: plain(net.name),
    status: plain(net.status),
    type: plain(net.type),
    mac: plain(net.mac),
    assignedAddresses: net.assignedAddresses || [],
    portDeviceName: plain(net.portDeviceName),
    allowDNS: net.allowDNS === true,
    allowDefault: net.allowDefault === true,
    allowGlobal: net.allowGlobal === true,
    allowManaged: net.allowManaged === true
  }
}

function normalizeNetworks(raw) {
  var out = []
  var list = asArray(raw)
  for (var i = 0; i < list.length; i++) {
    var n = normalizeNetwork(list[i])
    if (n && n.id !== "") out.push(n)
  }
  return sortNetworks(out)
}

function normalizePeers(raw) {
  var out = []
  var list = asArray(raw)
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (!p) continue
    out.push({
      address: plain(p.address),
      role: plain(p.role),
      latency: p.latency || 0,
      version: plain(p.version),
      versionMajor: p.versionMajor || 0,
      versionMinor: p.versionMinor || 0
    })
  }
  out.sort(function(a, b) { return a.address < b.address ? -1 : a.address > b.address ? 1 : 0 })
  return out
}

function controllerNetworkId(net) {
  if (!net) return ""
  var id = plain(net.nwid)
  if (id !== "") return id
  return plain(net.id)
}

function controllerNetworkLabel(net) {
  if (!net) return "Unknown"
  var name = plain(net.name)
  if (name !== "") return name
  return controllerNetworkId(net) || "Unknown"
}

function controllerPoolSummary(net) {
  if (!net || !net.ipAssignmentPools || !net.ipAssignmentPools.length) return "—"
  var p = net.ipAssignmentPools[0]
  if (!p) return "—"
  return plain(p.ipRangeStart) + " – " + plain(p.ipRangeEnd)
}

function controllerDnsSummary(net) {
  if (!net || !net.dns) return "—"
  var domain = plain(net.dns.domain)
  var servers = net.dns.servers || []
  var parts = []
  if (domain !== "") parts.push(domain)
  for (var i = 0; i < servers.length; i++) parts.push(plain(servers[i]))
  return parts.length ? parts.join(", ") : "—"
}

function memberLabel(mem) {
  if (!mem) return "Unknown"
  var name = plain(mem.name)
  if (name !== "") return name
  return plain(mem.address) || "Unknown"
}

function normalizeControllerNetwork(net) {
  if (!net) return null
  var id = controllerNetworkId(net)
  if (id === "") return null
  var pools = net.ipAssignmentPools || []
  var normPools = []
  for (var i = 0; i < pools.length; i++) {
    var p = pools[i]
    if (!p) continue
    normPools.push({
      ipRangeStart: plain(p.ipRangeStart),
      ipRangeEnd: plain(p.ipRangeEnd)
    })
  }
  var dns = net.dns || {}
  var dnsServers = dns.servers || []
  var normDnsServers = []
  for (var j = 0; j < dnsServers.length; j++) normDnsServers.push(plain(dnsServers[j]))
  var routes = net.routes || []
  var normRoutes = []
  for (var k = 0; k < routes.length; k++) {
    var route = routes[k]
    if (!route) continue
    normRoutes.push({ target: plain(route.target) })
  }
  return {
    id: id,
    nwid: id,
    name: plain(net.name),
    private: net.private === true,
    enableBroadcast: net.enableBroadcast === true,
    mtu: net.mtu || 0,
    multicastLimit: net.multicastLimit || 0,
    v4AssignZT: net.v4AssignMode && net.v4AssignMode.zt === true,
    v6AssignSixPlane: net.v6AssignMode && (net.v6AssignMode["6plane"] === true || net.v6AssignMode.sixplane === true),
    v6AssignRFC4193: net.v6AssignMode && net.v6AssignMode.rfc4193 === true,
    v6AssignZT: net.v6AssignMode && net.v6AssignMode.zt === true,
    ipAssignmentPools: normPools,
    dns: { domain: plain(dns.domain), servers: normDnsServers },
    routes: normRoutes,
    routeCount: normRoutes.length,
    rulesJson: rulesToJson(net.rules),
    ruleCount: (net.rules && net.rules.length) || 0
  }
}

function rulesToJson(rules) {
  if (!rules || !rules.length) return '[{"type":"ACTION_ACCEPT"}]'
  try {
    return JSON.stringify(rules)
  } catch (e) {
    return '[{"type":"ACTION_ACCEPT"}]'
  }
}

function splitCsv(value) {
  var parts = plain(value).split(",")
  var out = []
  for (var i = 0; i < parts.length; i++) {
    var p = parts[i].trim()
    if (p !== "") out.push(p)
  }
  return out
}

function controllerRoutesToString(routes) {
  if (!routes || !routes.length) return ""
  var parts = []
  for (var i = 0; i < routes.length; i++) {
    var r = routes[i]
    if (!r) continue
    var line = plain(r.target)
    if (plain(r.via) !== "") line += ";" + plain(r.via)
    if (line !== "") parts.push(line)
  }
  return parts.join(",")
}

function dnsServersToCsv(servers) {
  if (!servers || !servers.length) return ""
  var out = []
  for (var i = 0; i < servers.length; i++) {
    var s = plain(servers[i])
    if (s !== "") out.push(s)
  }
  return out.join(", ")
}

function controllerNetworkFormPayload(opts) {
  opts = opts || {}
  var net = opts.net || {}
  var plan = opts.plan || {}
  var poolStart = plain(opts.poolStart)
  var poolEnd = plain(opts.poolEnd)
  if (poolStart === "") poolStart = plain(plan.poolStart)
  if (poolEnd === "") poolEnd = plain(plan.poolEnd)
  var cidr = plain(opts.cidr)
  if (cidr === "") cidr = plain(plan.cidr)
  var routes = plain(opts.routes)
  if (routes === "") routes = plain(plan.routes)
  if (routes === "" && cidr !== "") routes = cidr
  var mtu = parseInt(plain(opts.mtu) || plain(plan.mtu) || "2800", 10)
  var multicastLimit = parseInt(plain(opts.multicastLimit) || plain(plan.multicastLimit) || "32", 10)
  if (isNaN(mtu) || mtu <= 0) mtu = 2800
  if (isNaN(multicastLimit) || multicastLimit <= 0) multicastLimit = 32
  return {
    name: plain(opts.name) || plain(net.name) || "network",
    private: opts.private !== undefined ? opts.private === true : (net.private === true),
    enableBroadcast: opts.enableBroadcast !== undefined ? opts.enableBroadcast === true : (net.enableBroadcast === true),
    mtu: mtu,
    multicastLimit: multicastLimit,
    poolStart: poolStart,
    poolEnd: poolEnd,
    cidr: cidr,
    routes: routes,
    dnsDomain: plain(opts.dnsDomain) || plain((net.dns && net.dns.domain)) || plain(plan.dnsDomain),
    dnsServers: plain(opts.dnsServers) || dnsServersToCsv(net.dns && net.dns.servers) || plain(plan.dnsServers),
    rules: plain(opts.rules) || plain(net.rulesJson) || plain(plan.rules),
    v4ZT: opts.v4ZT !== undefined ? opts.v4ZT === true : (net.v4AssignZT === true),
    v6SixPlane: opts.v6SixPlane !== undefined ? opts.v6SixPlane === true : (net.v6AssignSixPlane === true),
    v6RFC4193: opts.v6RFC4193 !== undefined ? opts.v6RFC4193 === true : (net.v6AssignRFC4193 === true),
    v6ZT: opts.v6ZT !== undefined ? opts.v6ZT === true : (net.v6AssignZT === true)
  }
}

function controllerNetworkUpdatePayload(opts) {
  return controllerNetworkFormPayload(opts)
}

function normalizeControllerNetworks(raw) {
  var out = []
  var list = asArray(raw)
  for (var i = 0; i < list.length; i++) {
    var n = normalizeControllerNetwork(list[i])
    if (n) out.push(n)
  }
  return sortNetworks(out)
}

function normalizeControllerMember(mem) {
  if (!mem) return null
  var address = plain(mem.address)
  if (address === "") address = plain(mem.id)
  if (address === "") return null
  var ips = mem.ipAssignments || []
  var normIps = []
  for (var i = 0; i < ips.length; i++) normIps.push(plain(ips[i]))
  return {
    address: address,
    nwid: plain(mem.nwid),
    name: plain(mem.name),
    authorized: mem.authorized === true,
    activeBridge: mem.activeBridge === true,
    noAutoAssignIps: mem.noAutoAssignIps === true,
    ipAssignments: normIps,
    version: String(mem.vMajor || 0) + "." + String(mem.vMinor || 0) + "." + String(mem.vRev || 0)
  }
}

function normalizeControllerMembers(raw) {
  var out = []
  var list = asArray(raw)
  for (var i = 0; i < list.length; i++) {
    var m = normalizeControllerMember(list[i])
    if (m) out.push(m)
  }
  out.sort(function(a, b) {
    var an = memberLabel(a).toLowerCase()
    var bn = memberLabel(b).toLowerCase()
    return an < bn ? -1 : an > bn ? 1 : 0
  })
  return out
}

function controllerMemberUpdatePayload(mem, overrides) {
  overrides = overrides || {}
  var ips = overrides.ipAssignments || mem.ipAssignments || []
  var normIps = []
  for (var i = 0; i < ips.length; i++) normIps.push(plain(ips[i]))
  return {
    authorized: overrides.authorized !== undefined ? overrides.authorized === true : mem.authorized === true,
    activeBridge: overrides.activeBridge !== undefined ? overrides.activeBridge === true : mem.activeBridge === true,
    noAutoAssignIps: overrides.noAutoAssignIps !== undefined ? overrides.noAutoAssignIps === true : mem.noAutoAssignIps === true,
    name: overrides.name !== undefined ? plain(overrides.name) : plain(mem.name),
    ipAssignments: normIps
  }
}

function mergeMemberIp(mem, ip) {
  var next = (mem.ipAssignments || []).slice()
  var value = plain(ip)
  if (value === "") return next
  for (var i = 0; i < next.length; i++)
    if (next[i] === value) return next
  next.push(value)
  return next
}

function removeMemberIp(mem, ip) {
  var value = plain(ip)
  var next = []
  for (var i = 0; i < (mem.ipAssignments || []).length; i++) {
    if (mem.ipAssignments[i] !== value) next.push(mem.ipAssignments[i])
  }
  return next
}

function ipHostKey(ip) {
  var host = plain(ip).split("/")[0].trim()
  var parts = host.split(".")
  if (parts.length !== 4) return ""
  for (var i = 0; i < 4; i++) {
    var n = parseInt(parts[i], 10)
    if (isNaN(n)) return ""
    parts[i] = String(n)
  }
  return parts.join(".")
}

function suggestMemberIp(network, members) {
  if (!network || !network.ipAssignmentPools || !network.ipAssignmentPools.length) return ""
  var pool = network.ipAssignmentPools[0]
  var startKey = ipHostKey(pool.ipRangeStart)
  var endKey = ipHostKey(pool.ipRangeEnd)
  if (startKey === "" || endKey === "") return ""
  var startParts = startKey.split(".")
  var endParts = endKey.split(".")
  if (startParts[0] !== endParts[0] || startParts[1] !== endParts[1] || startParts[2] !== endParts[2])
    return ""
  var used = {}
  var list = members || []
  for (var i = 0; i < list.length; i++) {
    var ips = list[i].ipAssignments || []
    for (var j = 0; j < ips.length; j++) {
      var key = ipHostKey(ips[j])
      if (key !== "") used[key] = true
    }
  }
  var lo = parseInt(startParts[3], 10)
  var hi = parseInt(endParts[3], 10)
  if (isNaN(lo) || isNaN(hi)) return ""
  for (var n = lo; n <= hi; n++) {
    var candidate = startParts[0] + "." + startParts[1] + "." + startParts[2] + "." + String(n)
    if (!used[candidate]) return candidate
  }
  return ""
}

function authorizeMemberPayload(network, members) {
  var payload = {
    authorized: true,
    noAutoAssignIps: false
  }
  var ip = suggestMemberIp(network, members)
  if (ip !== "") payload.ipAssignments = [ip]
  return payload
}

function controllerNetworkDetailText(net) {
  if (!net) return ""
  var lines = []
  lines.push("Network ID: " + plain(net.id))
  lines.push("Access: " + (net.private ? "Private — nodes need approval" : "Public — open join"))
  lines.push("Broadcast: " + (net.enableBroadcast ? "On — allow Ethernet broadcast" : "Off"))
  lines.push("Address pool: " + controllerPoolSummary(net) + " — controller assigns from this range")
  lines.push("MTU: " + String(net.mtu || 2800) + " bytes — max packet size on virtual network")
  lines.push("Multicast limit: " + String(net.multicastLimit || 32) + " — max multicast group members")
  lines.push("IPv4 assign: " + (net.v4AssignZT ? "ZeroTier managed" : "manual only"))
  lines.push("DNS: " + controllerDnsSummary(net))
  lines.push("Routes: " + String(net.routeCount || 0) + " · Rules: " + String(net.ruleCount || 0))
  return lines.join("\n")
}

function parseIpv4ThirdOctet(ip) {
  var parts = plain(ip).split(".")
  if (parts.length !== 4) return -1
  var n = parseInt(parts[2], 10)
  return isNaN(n) ? -1 : n
}

function parseCidrThirdOctet(cidr) {
  var base = plain(cidr).split("/")[0]
  return parseIpv4ThirdOctet(base)
}

function suggestControllerNetworkPlan(networks) {
  var used = {}
  var list = networks || []
  for (var i = 0; i < list.length; i++) {
    var net = list[i]
    if (!net) continue
    var pools = net.ipAssignmentPools || []
    for (var p = 0; p < pools.length; p++) {
      var pool = pools[p]
      if (!pool) continue
      var a = parseIpv4ThirdOctet(pool.ipRangeStart)
      var b = parseIpv4ThirdOctet(pool.ipRangeEnd)
      if (a >= 0) used[a] = true
      if (b >= 0) used[b] = true
    }
    // routeCount only in normalized model — scan raw routes if present
    var routes = net.routes || []
    for (var r = 0; r < routes.length; r++) {
      var route = routes[r]
      if (!route) continue
      var t = parseCidrThirdOctet(route.target)
      if (t >= 0) used[t] = true
    }
    // infer from pool summary pattern 10.147.N.x
    var poolStart = pools.length ? plain(pools[0].ipRangeStart) : ""
    var t2 = parseIpv4ThirdOctet(poolStart)
    if (t2 >= 0) used[t2] = true
  }

  var third = 20
  for (; third < 255; third++) {
    if (!used[third]) break
  }
  if (third >= 255) third = 20

  return {
    poolStart: "10.147." + third + ".1",
    poolEnd: "10.147." + third + ".254",
    cidr: "10.147." + third + ".0/24",
    routes: "10.147." + third + ".0/24",
    dnsDomain: "zt.local",
    dnsServers: "10.147." + third + ".1",
    mtu: "2800",
    multicastLimit: "32",
    rules: '[{"type":"ACTION_ACCEPT"}]'
  }
}
