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
- Bookmarks
- Notes

### 🎨 Reader customization
- Apple Books-style reader: full-screen pages with floating controls, whole-book page numbers, Contents (table of contents, bookmarks, highlights)
- Font size & family
- Themes: Original, Quiet, Paper, Bold, Calm, Focus, following the system dark mode
- Line Guide: keeps the line you're reading prominent (dim or blur the rest)
- Layout tuning (line height, margins)

### 🔍 Search
- Full-text search ✅ (runs off the main thread, opens the match highlighted)

### 💾 Persistence
- Reading position tracking
- Highlight/bookmark persistence: use the built-in `DCJSONReaderStore`, or plug in your own storage

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
- [x] State persistence helpers
- [x] Search engine
- [ ] Performance optimizations (large books)
- [ ] Accessibility improvements (VoiceOver, dynamic type)

---

## 💾 Using the built-in store

`DCJSONReaderStore` keeps highlights, notes, bookmarks and the reading position in one JSON file per book
(`Application Support/DCEpubReaderKit` by default). Wrap it in `DCStoreReaderDelegate` and pass that as the reader's delegate:

```swift
let store = DCJSONReaderStore()
let position = await store.position(bookId: book.uniqueIdentifier)

DCReaderViewBuilder.build(
    book,
    spineIndex: position?.spineIndex ?? 0,
    initialCoords: position?.coords,
    delegate: DCStoreReaderDelegate(store: store)
)
```

To use your own storage, implement `DCReaderCoordsProtocol` directly (as the example app does with Realm),
or implement `DCHighlightStoreProtocol` + `DCReadingPositionStoreProtocol` and keep `DCStoreReaderDelegate`.

## 🔍 Search

The reader's toolbar includes search. To search outside the reader, use the engine directly:

```swift
let engine = DCEpubSearchEngine(book: book)
let results = await engine.search("whale")   // [DCSearchResult] with chapter, snippet and match
```

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
