# Contributing to Copibara

Thanks for your interest in contributing to Copibara! 🐾

## Getting Started

### Prerequisites
- macOS 14.0+
- Xcode 15+ or Swift 5.9+
- An Apple Developer account (for code signing)

### Build from Source
```bash
cd Copibara
swift build
swift run
```

### Build a Signed DMG
```bash
# Copy .env.example to .env and fill in your credentials
cd Copibara
./build.sh
```

## How to Contribute

### Reporting Bugs
Open an [issue](https://github.com/your-username/Copibara/issues) with:
- macOS version
- Steps to reproduce
- Expected vs actual behavior

### Submitting Changes
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -m 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

### Code Style
- Follow existing Swift code conventions
- Use `// MARK: -` for section organization
- Keep functions focused and small
- Add comments for non-obvious logic

### Icon Contest 🎨
We're running a community icon contest! Submit your capybara icon design as a PR to `assets/community-icons/`. See [README](README.md) for details.

## Project Structure
```
Copibara/
├── Sources/
│   ├── CopibaraApp.swift      # App entry point
│   ├── Models/                # Data models
│   ├── Services/              # Clipboard monitor, hotkeys
│   ├── Views/                 # SwiftUI views
│   └── Theme/                 # Design tokens
├── build.sh                   # Build + sign + notarize
└── Package.swift              # SPM manifest
```

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
