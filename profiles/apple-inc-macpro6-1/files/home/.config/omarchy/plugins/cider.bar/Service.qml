import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var player: findCiderPlayer()
  readonly property bool connected: player !== null
  readonly property bool hasMedia: connected && !!(title || artist || album)
  readonly property bool playing: connected && player.isPlaying === true
  readonly property string title: connected ? boundedText(player.trackTitle, 256) : ""
  readonly property string artist: connected ? boundedText(player.trackArtist, 256) : ""
  readonly property string album: connected ? boundedText(player.trackAlbum, 256) : ""
  readonly property string artUrl: connected ? safeArtworkUrl(player.trackArtUrl) : ""
  readonly property string playbackState: !connected ? "Not running" : playing ? "Playing" : hasMedia ? "Paused" : "Stopped"

  function isCiderPlayer(candidate) {
    return !!candidate && String(candidate.dbusName || "") === "org.mpris.MediaPlayer2.cider"
  }

  function boundedText(value, maxLength) {
    var text = String(value || "").replace(/[\u0000-\u001f\u007f-\u009f]/g, " ").trim()
    return text.length > maxLength ? text.slice(0, maxLength) : text
  }

  function safeArtworkUrl(value) {
    var url = boundedText(value, 2048)
    var appleArtwork = /^https:\/\/is[1-5]-ssl\.mzstatic\.com\/image\/thumb\/[A-Za-z0-9%._~!$&'()*+,;=:@\/-]+\/[0-9]{1,4}x[0-9]{1,4}(?:bb|sr)\.(?:jpg|jpeg|png)$/i
    if (!appleArtwork.test(url)) return ""
    return url.replace(/\/[0-9]{1,4}x[0-9]{1,4}(?:bb|sr)\.(?:jpg|jpeg|png)$/i, "/256x256bb.jpg")
  }

  function findCiderPlayer() {
    for (var i = 0; i < players.length; i++) {
      if (isCiderPlayer(players[i])) return players[i]
    }
    return null
  }

  function launch() {
    Quickshell.execDetached(["/usr/bin/uwsm-app", "--", "/usr/bin/gtk-launch", "cider"])
    return true
  }

  function runAction(action) {
    var target = player
    if (!target) return false

    if (action === "next" && target.canGoNext) {
      target.next()
      return true
    }
    if (action === "previous" && target.canGoPrevious) {
      target.previous()
      return true
    }
    if (action === "playPause") {
      if (target.isPlaying && target.canPause) target.pause()
      else if (!target.isPlaying && target.canPlay) target.play()
      else if (target.canTogglePlaying) target.togglePlaying()
      else return false
      return true
    }
    return false
  }

  function primaryAction() {
    return connected ? runAction("playPause") : launch()
  }

  function statusJson() {
    return JSON.stringify({
      connected: connected,
      playing: playing,
      state: playbackState,
      title: title,
      artist: artist,
      album: album,
      artUrl: artUrl,
      dbusName: player ? String(player.dbusName || "") : "",
      canGoPrevious: player ? !!player.canGoPrevious : false,
      canGoNext: player ? !!player.canGoNext : false,
      canPlay: player ? !!player.canPlay : false,
      canPause: player ? !!player.canPause : false
    })
  }

  IpcHandler {
    target: "cider"

    function status(): string { return root.statusJson() }
    function playPause(): string { return root.runAction("playPause") ? "ok" : "unhandled" }
    function next(): string { return root.runAction("next") ? "ok" : "unhandled" }
    function previous(): string { return root.runAction("previous") ? "ok" : "unhandled" }
  }
}
