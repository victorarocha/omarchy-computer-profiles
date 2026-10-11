# Ztnodes — intended features & architecture

Omarchy bar plugin for [ZeroTier](https://www.zerotier.com/). Unofficial third-party widget; not affiliated with ZeroTier, Inc.

Feature target: **[ztnui](https://github.com/brukberhane/ztnui)** (client + controller). UI tone: between **omarchy.tailscale** (rich panel, keyboard, copy) and **[omanodes](https://github.com/jwhall/omarchy-omanodes)** (ZeroTier-focused, security-conscious).

---

## Constraints (agreed)

| Constraint | Decision |
|------------|----------|
| No plugin build step | Backend is **bash + python3 + curl + secret-tool** only. No `go build`, no bundled binaries. |
| Backend transport | **ZeroTier One Service API** (`http://127.0.0.1:<port>/…`, header `X-ZT1-Auth`). Not `zerotier-cli` for data (except optional service checks). |
| ztnui relationship | Reuse **API paths & behaviour** from ztnui’s `api/` package; do **not** spawn the ztnui TUI. Token storage is **compatible** with ztnui’s libsecret entry when present. |
| Token security | See [Authentication](#authentication). Never pass token on argv; never log token; never persist plaintext in plugin tree. |

---

## Architecture

```
BarWidget.qml ──► Panel.qml
       │                │
       └──── Process ───┘
                │
         bin/ztn-api (bash)
                │
    ┌───────────┼───────────┐
    │           │           │
 secret-tool   curl    ~/.config/…/config.json
 (keyring)         │
                   ▼
         zerotier-one :9993 (Service API)
```

All backend stdout is a JSON **envelope**:

```json
{ "ok": true, "data": { … } }
{ "ok": false, "error": "…", "needsAuth": true }
```

QML parses with `JSON.parse` only; never eval untrusted strings.

---

## Authentication

### Problem

`authtoken.secret` is mode `0600`, owned by `zerotier-one`. Unprivileged bar process cannot read it every poll (Omanodes solves this with polkit on **every** call — bad UX).

### Resolution order (`bin/lib/auth.sh`)

1. **Plugin keyring** — `secret-tool lookup service io.github.brukberhane.ztnodes username auth-token`
2. **ztnui keyring (compatible)** — `secret-tool lookup service ztnui username zerotier-auth-token`
3. **OS token file** — `/var/lib/zerotier-one/authtoken.secret` only if **already readable** by the session user (e.g. group `640` — user opt-in, not default)

### Store / clear

| Command | Behaviour |
|---------|-----------|
| `ztn-api auth status` | `{ hasToken, source, serviceReachable }` — **never** includes token |
| `ztn-api auth store` | Read token from **stdin only** (panel pipe). Validate length. Store via `secret-tool store`. Mode `umask 077`. |
| `ztn-api auth clear` | Delete plugin, legacy, and ztnui keyring entries (not `authtoken.secret`) |

### UI first-run

Panel shows auth card: paste 24-char token → `auth store` via Process stdin → keyring. Optional hint: `sudo cat /var/lib/zerotier-one/authtoken.secret` in terminal (user copies manually; plugin never runs sudo for reads).

### API host allowlist

`config.json` `host` must be loopback or private IPv4/IPv6. Public IPs, `@`, slashes, and hostnames other than `localhost` fall back to `127.0.0.1`. Port clamped to `1–65535`.

### Leak prevention checklist

- [x] Token never in argv for child HTTP processes
- [x] Token never in envelope JSON
- [x] Token never written under `~/.config/omarchy/plugins/…`
- [x] Authenticated HTTP via `printf token | zt_launcher.py zt_helper.py` — token on stdin, never argv. (memfd fd 3 does not survive Quickshell Process.)
- [x] Controller batch HTTP in `bin/lib/zt_helper.py` — token on fd 3 only
- [x] API responses capped at 8 MiB; stdin JSON is one value (no EOF wait); batch max 32 items and 8 MiB aggregate output budget
- [x] Member update payloads validated (`member_body.py`)
- [x] Backend stderr for errors only; QML must not echo stderr to notifications
- [x] Controller `name` fields sanitized (`Model.js` `plain()`) before any `Text`

---

## Backend commands (`bin/ztn-api`)

### Phase 1 (implemented / in progress)

| Command | API | Notes |
|---------|-----|-------|
| `auth status` | — | Token presence + API ping |
| `auth store` | — | stdin |
| `auth clear` | — | |
| `status` | `GET /status` | Node address, version, online |
| `networks` | `GET /network` | Joined networks |
| `network get <nwid>` | `GET /network/{id}` | Detail |
| `network join <nwid>` | `POST /network/{id}` | `{}` body |
| `network leave <nwid>` | `DELETE /network/{id}` | |
| `network set <nwid> <key> <bool>` | `POST /network/{id}` | `allowDNS`, `allowDefault`, `allowGlobal`, `allowManaged` |
| `peers` | `GET /peer` | |
| `controller status` | `GET /controller` | Hide Server tab if not controller |

### Phase 1.5 — controller (planned)

| Command | API |
|---------|-----|
| `controller networks` | `GET /controller/network` |
| `controller network get <nwid>` | `GET /controller/network/{id}` |
| `controller network create` | `POST /controller/network/{id}______` |
| `controller network delete <nwid>` | `DELETE /controller/network/{id}` |
| `controller members <nwid>` | `GET /controller/network/{id}/member` |
| `controller member update …` | `POST …/member/{node}` |
| `controller member delete …` | `DELETE …/member/{node}` |

### Phase 2 — advanced (planned)

- IP pools, routes, DNS, flow rules (forms or “Open ztnui” fallback)
- Hidden members (persist in plugin config JSON)
- Notifications on `ACCESS_DENIED` → `OK` transitions

---

## UI plan

### Bar (`BarWidget.qml`)

- ZeroTier glyph / bundled logo
- Tooltip: node id snippet + joined count
- Alert tint on error or no auth
- Left: toggle panel · Middle: refresh · Right: (reserved)

### Panel (`Panel.qml`) — phase 1

**Header:** node address, version, online dot, refresh.

**Tabs:** `Client` | `Server` (Server visible only when `controller.status.controller === true`).

**Client tab**

- Network list (name, status, type, assigned IPs)
- Row actions: detail, leave (confirm with **nwid** in dialog), copy IP / nwid
- Join by 16-hex ID
- Detail subview: toggles allowDNS / allowDefault / allowGlobal / allowManaged
- Peers subview (address, role, latency, version)

**Overlays (later):** Node info, Settings (API host/port — config file).

### Keyboard (target)

| Key | Action |
|-----|--------|
| j/k, arrows | navigate |
| Enter | open / activate |
| c | copy (IP / nwid) |
| n | join |
| l | leave (confirm) |
| p | peers |
| r | refresh |
| Tab | Client ↔ Server |
| Esc | back / close |

---

## Config

`~/.config/io.github.brukberhane.ztnodes/config.json`:

```json
{ "host": "127.0.0.1", "port": 0 }
```

`port: 0` → read `/var/lib/zerotier-one/zerotier-one.port`.

---

## Phases

| Phase | Scope |
|-------|--------|
| **1** | Bar, Client tab, auth, join/leave, toggles, peers, controller detect |
| **1.5** | Server tab: network CRUD, member auth/IP management |
| **2** | Rules/pools/routes, hidden members, richer notifications |

---

## References

- [ZeroTier Service API OpenAPI](https://docs.zerotier.com/openapi/service/v1.json)
- [ztnui](https://github.com/brukberhane/ztnui) — feature reference & keyring compat
- [omarchy.tailscale](file:///usr/share/omarchy/shell/plugins/panels/tailscale/) — panel UX patterns
- [omanodes](https://github.com/jwhall/omarchy-omanodes) — ZeroTier widget security notes

---

## Plugin ID

`io.github.brukberhane.ztnodes` — display name **Ztnodes**.
