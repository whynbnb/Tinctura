> Vibe-coded with DeepSeek V4.1 Flash / OpenCode

English · [简体中文](README.zh-CN.md)

<p align="center">
  <img src="docs/appicon.png" width="144" alt="Tinctura app icon">
</p>

<h1 align="center">Tinctura</h1>

<p align="center">
  A native macOS color toolkit — screen picking, image palette analysis, color walk and WCAG contrast checks.<br>
  Built with Swift 6 and SwiftUI.
</p>

<p align="center">
  <a href="https://github.com/whynbnb/Tinctura">GitHub</a> ·
  <a href="LICENSE">MIT License</a>
</p>

---

## Features

### 1. Screen picking
- **System sampler** (`NSColorSampler`) — no extra permission, shortcut `⌘⇧C`
- **Magnifier picker** — pixel-level live magnifier with a local context view and zoom (needs Screen Recording)
- Manual HSB sliders, HEX input and preset swatches
- One-click copy in many formats: HEX / HEXA / RGB / RGBA / HSB / HSL / CMYK / SwiftUI / NSColor / CSS

### 2. Image palette analysis
- Drag & drop or open an image (PNG / JPEG / TIFF / HEIC / WebP)
- K-Means dominant-color extraction (3–16 colors, adjustable)
- Proportion bar + average color
- Click anywhere on the image to sample a color

### 3. Color walk
10 modes that roam through color space automatically:

| Mode | Description |
|------|-------------|
| Hue spin | Rotate evenly around the hue wheel |
| Complementary jump | Oscillate between complementary colors |
| Analogous drift | Gently wander through neighboring hues |
| Triadic rhythm | Switch on a triadic rhythm |
| Pastel drift | Low-saturation soft drift |
| Neon pulse | High-saturation neon pulse |
| Monochrome depth | Fixed hue, varying lightness |
| Random walk | Random walk with inertia |
| Gradient path | Interpolate back and forth between two endpoints |
| Warm ↔ cool | Alternate between warm and cool tints |

Speed and step size are adjustable, and the trail can be pushed to history.

### 4. Foreground / background contrast (WCAG)
- Independent foreground and background colors (screen pick, magnifier, swatches, HEX, HSB)
- Live text / button preview with adjustable size and bold
- Contrast ratio + meter with the 3 / 4.5 / 7 thresholds
- WCAG 2.x checklist: AAA normal, AA normal, AAA/AA large, AA UI
- Translucent foreground compositing over the background

### 5. History
Locally persisted (up to 80 colors) with search, context menu and grid browsing.

## Requirements

- macOS 15.0+
- Xcode 16+ / Swift 6.0+

## Build & run

### SwiftPM (command line)

```bash
swift build -c release
swift run
```

You can also open `Package.swift` in Xcode as a package.

### Xcode project (recommended for debugging / signing / permissions)

```bash
open Tinctura.xcodeproj
```

Select the **Tinctura** scheme → Run (`⌘R`).

If you change `project.yml`, regenerate the project:

```bash
xcodegen generate
```

Sources live in `Sources/Tinctura/`; the SwiftPM package and the Xcode project share the same source files.

## Permissions

| Feature | Permission |
|---------|------------|
| System sampler | None |
| Magnifier picker | Screen Recording (System Settings → Privacy & Security → Screen Recording) |

The app never prompts at launch. The system prompt is shown only when you first click **Magnifier pick**; if access is denied, use the in-app **Open Settings** button.

## Project structure

```
Tinctura/
├── Package.swift              # SwiftPM (swift build / swift run)
├── project.yml                # XcodeGen project definition
├── Tinctura.xcodeproj         # Xcode app project
├── docs/
│   └── appicon.png            # App icon (used in this README)
└── Sources/Tinctura/          # Shared sources
    ├── App/
    ├── Models/
    ├── Services/
    ├── Views/
    │   └── Components/
    └── Resources/
        └── Assets.xcassets    # App icon (used by Xcode)
```

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘⇧C` | System picker |
| `⌘C` | Copy current color (selected format) |
| `Esc` | Cancel magnifier pick |

## Open Source

Tinctura is open source and released under the **MIT License**.

- Repository: <https://github.com/whynbnb/Tinctura>
- License: [MIT](LICENSE)

Issues and pull requests are welcome. If you find a bug or have an idea, please open an issue on GitHub.

## License

MIT © 0x574859 — see [LICENSE](LICENSE) for the full text.
