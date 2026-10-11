# Omarchy Glass & Blur Control Plugin (`lutfi.glass`)

An interactive quick-control Quickshell bar widget for [Omarchy](https://omarchy.org/) (Arch Linux + Hyprland) to adjust window opacity, frosted glass blur, and top status bar blur in real time.

![Preview](preview.png)

## Features

- **Live Window Opacity**: Adjust active and inactive window opacity with instant preview.
- **Frosted Glass Blur**: Toggle and tune Hyprland's dual-Kawase blur passes and radius.
- **Top Bar Blur & Glass Tint Slider**: Toggle glass blur underneath the Omarchy top bar and fine-tune bar tint darkness (30%–95%) so text never clashes with bright wallpapers.
- **4 Bar Color Modes**:
  - **Theme Auto**: Dynamic luminance-adaptive contrast based on wallpaper.
  - **Theme Accent**: Pure theme foreground color (`Color.bar.text`), completely unshifted.
  - **Invert Palette**: High-contrast inverted palette.
  - **Custom Picker**: Full visual Canva/Adobe 2D color picker.
- **Canva / Adobe Visual Color Picker**:
  - 2D Saturation / Value (SV) gradient box with interactive crosshair dragger.
  - 1D 360° Rainbow Hue slider with draggable position thumb.
  - 8 curated aesthetic color swatches.
  - Live preview swatch + hex input field (`#hex`) with real-time IPC synchronization.
- **Quick Presets**: One-click presets for Solid (100%), Subtle (92%), Frosted (88%), and Deep (78%).
- **Seamless Persistence**: Writes clean overrides inside fenced markers in `~/.config/hypr/looknfeel.lua` and state toggles.

## Architecture

```mermaid
    A[Quickshell Bar Widget: Panel.qml] -->|execDetached| B[Helper: bin/glass-ctl]
    B -->|hyprctl eval| C[Hyprland Runtime]
    B -->|update @omarchy-glass block| D[~/.config/hypr/looknfeel.lua]
    B -->|update [bar] config| E[Omarchy Config: shell.toml & shell.json]
    D -->|auto-reload| C
    E -->|watchChanges| F[Omarchy Status Bar]
```

## Installation

### Via Omarchy Plugin Manager

```bash
omarchy plugin add https://github.com/lutfi-zain/omarchy-glass-blur.git --enable
```

### Manual Installation

Clone this repository directly into your Omarchy plugins directory:

```bash
git clone https://github.com/lutfi-zain/omarchy-glass-blur.git ~/.config/omarchy/plugins/lutfi.glass
```

Then add `lutfi.glass` to your `~/.config/omarchy/shell.json` in the `bar.layout.right` (or preferred) section:

```json
{
  "id": "lutfi.glass"
}
```

Reload plugins in the shell:

```bash
omarchy-shell shell rescanPlugins
```

## Uninstallation

### Via Omarchy Plugin Manager

```bash
omarchy plugin remove lutfi.glass
```

### Manual Removal

1. Remove the `"lutfi.glass"` entry from your `~/.config/omarchy/shell.json` under `bar.layout.right`.
2. Remove the plugin directory:
   ```bash
   rm -rf ~/.config/omarchy/plugins/lutfi.glass
   ```
3. Restart the Omarchy shell:
   ```bash
   omarchy restart shell
   ```

## Requirements

- [Omarchy](https://omarchy.org/) Quattro with Quickshell
- [Hyprland](https://hyprland.org/) with Lua configuration support
- Python 3

## License

MIT License &copy; 2026 Lutfi Zain
