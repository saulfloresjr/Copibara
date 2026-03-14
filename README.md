# 🐾 Copibara

**A lightweight, privacy-first clipboard manager for macOS.**

Copibara lives in your menu bar and silently captures everything you copy — text, links, code snippets, colors, and screenshots. Organize clips into custom boards, search your history instantly, and paste anything with a keyboard shortcut.

🌐 **[copibara.com](https://copibara.com)**

![Version](https://img.shields.io/badge/version-1.0.0-brightgreen) ![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/License-MIT-green)

---

## ✨ Features

- **📋 Smart Clipboard History** — Automatically captures text, links, code, and images
- **📸 Screenshot Capture** — Press `~` to capture screen regions directly into Copibara
- **📌 Custom Boards** — Organize clips into pinboards for different projects
- **⌨️ Keyboard-First** — `⌘⇧V` opens the picker, arrow keys navigate, Enter pastes
- **🔍 Instant Search** — Filter clips by content or type in real-time
- **🎯 Quick Paste** — Select any clip and it's instantly pasted into your active app
- **🔒 Privacy-First** — All data stored locally in `~/Library/Application Support/CopibaraManager/`
- **🪶 Lightweight** — Menu bar app, no dock icon, minimal resource usage

## 📦 Requirements

- macOS 14 (Sonoma) or later
- Xcode Command Line Tools (for building from source)

## 🚀 Build from Source

```bash
# Clone the repository
git clone https://github.com/saulfloresjr/Copibara.git
cd Copibara/Copibara

# Build with Swift Package Manager
swift build -c release

# The binary will be at .build/release/Copibara
```

### Create a Signed DMG (Optional)

If you have an Apple Developer ID and want to create a notarized DMG:

```bash
# Copy the example env and fill in your credentials
cp .env.example .env
# Edit .env with your Apple ID, app-specific password, and Team ID

# Run the build script
./build.sh
# Output: dist/Copibara.dmg (signed + notarized + stapled)
```

## 🎹 Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘⇧V` | Open clipboard picker |
| `↑` `↓` | Navigate clips |
| `↩` | Paste selected clip |
| `⇥` | Switch board |
| `⎋` | Close picker |
| `~` | Capture screenshot region |
| `⌘` + Click | Multi-select clips |
| `⇧` + Click | Range select clips |

## 🏗️ Project Structure

```
Copibara/
├── Package.swift              # Swift Package Manager config
├── build.sh                   # Build, sign, notarize script
├── Copibara.entitlements      # macOS entitlements
├── .env.example               # Template for Apple credentials
└── Sources/
    ├── CopibaraApp.swift       # App entry point (MenuBarExtra)
    ├── Models/
    │   ├── CopibaraItem.swift  # Clipboard item model
    │   ├── CopibaraStore.swift # Data persistence & clipboard ops
    │   └── Pinboard.swift      # Board model
    ├── Services/
    │   ├── CopibaraMonitor.swift         # Clipboard polling
    │   ├── HotkeyService.swift           # Global hotkey (⌘⇧V)
    │   └── TildeScreenshotService.swift  # Screenshot capture (~)
    ├── Views/
    │   ├── ContentView.swift           # Main grid view
    │   ├── CopibaraCardView.swift      # Clip card component
    │   ├── CopibaraGridView.swift      # Grid layout
    │   ├── CopibaraPickerView.swift    # Quick picker (⌘⇧V)
    │   ├── FloatingPanel.swift         # Floating window host
    │   └── ...                         # Other view components
    └── Theme/
        └── DesignTokens.swift  # Design system tokens
```

## 🎨 Show Off Your Build

If you fork Copibara and add your own features, custom themes, or tweaks — I'd love to see it! Tag [@saulfloresjr](https://x.com/saulfloresjr) on X to share what you've built.

Checkout some of the [original design concepts](assets/brand/concepts/) we explored during development.

## 🔗 Links

- 🌐 **Website**: [copibara.com](https://copibara.com)
- 🐦 **X**: [@saulfloresjr](https://x.com/saulfloresjr)
- 🐛 **Issues**: [GitHub Issues](https://github.com/saulfloresjr/Copibara/issues)

## 📄 License

MIT — see [LICENSE](LICENSE) for details.

## 🤝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.
