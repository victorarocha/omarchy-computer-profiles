# Cider Bar
<img width="331" height="168" alt="image" src="https://github.com/user-attachments/assets/7171d906-3bc2-42d8-9582-72a1fe1da3b5" />

Dedicated Omarchy Shell status-bar controls for [Cider](https://cider.sh/), using the MPRIS player `org.mpris.MediaPlayer2.cider`.

## Features

- Playback status plus track, artist, and album metadata
- Tiny cover artwork in the bar and full artwork in the details popup when Cider publishes `mpris:artUrl`
- Left click: play/pause, or launch Cider when it is not running
- Middle click: next track
- Mouse wheel: previous/next track
- Right click: details popup with artwork and previous/play-pause/next buttons

All control and state use Quickshell's native MPRIS service. No polling helper or Cider API token is required.

## Requirements

- [Omarchy](https://omarchy.org/) with Omarchy Shell / Quickshell
- [Cider](https://cider.sh/) with Linux MPRIS enabled (`linux.useMpris: true`)

## Install

```bash
omarchy plugin add https://github.com/ndrewtx/omarchy-cider-bar.git --enable
```

The plugin ID is `cider.bar`. Enable it on the right of the bar if you added it without `--enable`:

```bash
omarchy plugin enable cider.bar --section right
```

Then restart the shell so the service IPC target is created:

```bash
omarchy restart shell
```

## Remove

```bash
omarchy plugin disable cider.bar
omarchy plugin remove cider.bar --yes
omarchy restart shell
```

Removal only deletes this plugin directory. It does not change Cider, other bar widgets, or unrelated `shell.json` settings.

## License

MIT. See [LICENSE](LICENSE).

External runtime dependencies are Omarchy Shell and Cider. This plugin does not bundle them.
