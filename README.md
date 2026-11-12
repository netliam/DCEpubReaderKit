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
- Highlights: filled, underline, squiggly and strikethrough, in any color
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
- iOS 16+ or Mac Catalyst 16+
- Xcode 15+

Add the package (this fork):

https://github.com/netliam/DCEpubReaderKit.git

In `Package.swift`:

```swift
.package(url: "https://github.com/netliam/DCEpubReaderKit.git", from: "0.1.0")
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

## ⚙️ Configuring the reader

Pass a `DCReaderConfiguration` to `build` to change what the reader does in your app. Everything has a default:

```swift
var configuration = DCReaderConfiguration()
configuration.defaults = UserDefaults(suiteName: "reader")!   // where settings and colors are kept
configuration.bookId = myBook.id                            // instead of the OPF identifier
configuration.showsSearch = false                           // also showsLineGuide, showsRotationLock, …
configuration.onClose = { dismissWindow(id: "reader") }      // the reader has its own window
configuration.onOpenExternalURL = { openURL($0) }
configuration.fonts = [DCReaderFont(name: "Literata", cssFamily: "Literata", files: [literataURL])]

DCReaderViewBuilder.build(book, spineIndex: 0, delegate: delegate, configuration: configuration)
```

### Highlight menu

`configuration.highlightMenu` sets the styles, colors and actions of the menus for selected text and for a tapped
highlight. The default is the Books-style menu.

```swift
configuration.highlightMenu.palettes = [
    DCHighlightPalette(style: .highlight, colors: [("Yellow", "#FACC15"), ("Green", "#4ADE80")]),
    DCHighlightPalette(style: .squiggly, colors: [("Crimson", "#DC143C"), ("Dodger Blue", "#1E90FF")])
]
configuration.highlightMenu.selectionActions = [.note, .search, .copy, .custom(sendToNotebook)]
configuration.highlightMenu.highlightActions = [.note, .copy, .delete]

let sendToNotebook = DCCustomHighlightAction(title: "Send to Notebook", systemImage: "book") { context in
    // context.text, .spineIndex, .coords, .cfi, and .highlight for a tapped highlight
}
```

The menu shows the colors of the current style (the tapped highlight's, or the last one used) and a Style submenu
for the others. A style with one color appears as its own button in the row. Highlights store `annotationStyle` and
`color` (`#RRGGBB`) separately and keep any color, including ones the palettes don't offer, so the delegate's
`save(highlight:)` gets them unchanged. Highlights saved by older versions (a `style` name such as `"pink"`) still
decode.

### Progress

Besides `handleCoords`, the delegate gets `handleProgress(book:progress:)` after each page turn: the fraction of the
whole book read, and the whole-book page and page count once the book has been counted (as the reader shows "11 of 39").

Use the same `bookId` with `DCStoreReaderDelegate(store:bookId:)`. For rotation lock, return
`DCReaderOrientationLock.supportedOrientations(for: window)` from your app delegate's
`application(_:supportedInterfaceOrientationsFor:)`.

## 🔁 EPUB CFI

Positions and highlights are stored as the reader's own `coords`. To sync with CFI-based readers (epub.js and others),
convert with `DCCFIConverter`:

```swift
let converter = DCCFIConverter(book: book)
let cfi = await converter.cfi(fromCoords: highlight.coords, spineIndex: highlight.spineIndex)
let place = await converter.coords(fromCFI: "epubcfi(/6/4[ch1]!/4/2/1:5)")   // (spineIndex, coords)
```

The spine step (`/6` above) is `<spine>`'s real position in the book's OPF (`DCEpubBook.spineStep`), as foliate-js and
epub.js compute it.

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
