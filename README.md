# 📚 DCEpubReaderKit

> ⚠️ **Status:** Work in progress. The library is not production-ready yet.

**DCEpubReaderKit** is a modular Swift library for building EPUB readers (EPUB 2 & 3) in iOS apps. It focuses on flexibility, clean architecture, and full control over the reading experience — without external service dependencies.

Designed for both **UIKit** and **SwiftUI**, it provides the core building blocks needed to implement a modern reader: parsing, rendering, navigation, and user interaction (highlights, bookmarks, etc.).

---

## ✨ What it aims to solve

Most EPUB solutions are either:
- Too rigid (hard to customize UI/UX)
- Too heavy (external SDKs, lock-ins)
- Too opaque (limited control over rendering)

**DCEpubReaderKit** takes the opposite approach:
- You own the UI
- You control persistence
- You extend the engine

---

## 🚀 Features (current & planned)

### 📖 Core EPUB support
- EPUB 2 parsing ✅
- EPUB 3 parsing 🚧
- OPF / NCX / NAV support
- Resource handling (HTML, CSS, images)

### 🧭 Navigation
- Chapter-based navigation
- Table of contents generation
- Horizontal pagination ✅ (`UIPageViewController`, curl or slide transition)
- Vertical pagination 🚧

### 🖍️ User interaction
- Text selection
- Highlights
- Bookmarks (planned)
- Notes

### 🎨 Reader customization
- Font size & family
- Themes (light, dark, red…)
- Layout tuning (line height, margins)

### 🔍 Search
- Full-text search (planned)

### 💾 Persistence
- Reading position tracking
- Highlight/bookmark persistence (engine ready, storage up to integrator)

---

## 🧱 Architecture

- 100% Swift
- `WKWebView`-based rendering layer
- Modular design (parser, renderer, models separated)
- No external dependencies

The library is intentionally **unopinionated about storage and UI**, so it can fit different app architectures (VIP, MVVM, etc.).

---

## 📦 Installation

### Swift Package Manager

**Requirements:**
- iOS 16+
- Xcode 15+

Add the package:

https://github.com/novecapa/DCEpubReaderKit.git

In `Package.swift`:

```swift
.package(url: "https://github.com/novecapa/DCEpubReaderKit.git", branch: "main")
```

Then:

```swift
.product(name: "DCEpubReaderKit", package: "DCEpubReaderKit")
```

---

## 🛠️ Roadmap

- [x] EPUB2 parsing
- [ ] EPUB3 full support
- [ ] Vertical pagination
- [x] Horizontal pagination
- [x] Highlights & bookmarks
- [ ] State persistence helpers
- [ ] Search engine
- [ ] Performance optimizations (large books)
- [ ] Accessibility improvements (VoiceOver, dynamic type)

---

## 🧪 Project maturity

This project is currently:
- In active development
- API unstable
- Not recommended for production use yet

Expect breaking changes until a `1.0.0` release.

---

## 🤝 Contributing

Contributions are welcome, especially in:
- EPUB edge cases
- Rendering bugs
- Performance improvements
- Accessibility

Basic flow:
1. Fork
2. Create branch (`feature/...`)
3. Commit clearly
4. Open PR

---

## ⚖️ License

Full license text in LICENSE file

---

## 🧩 Author

**Josep Cerdá Penadés**  
Senior iOS Developer  
https://github.com/novecapa

---

## 💡 Notes

- This is a **low-level reader engine**, not a plug-and-play UI component.
- If you're looking for a "drop-in reader", this might not be it.
- If you want control and extensibility, you're in the right place.
