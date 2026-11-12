# DCEpubReaderKit: work log

Handoff notes for continuing this work in Claude Code. They cover everything done on the `feature/roadmap-items` branch, which is not pushed.

## Project at a glance

- **Package:** an SPM package for iOS 16+ (swift-tools 6.2).
- **Modules:**
  - `DCEpubCore`: models, persistence and search.
  - `DCEpubParser`: OPF, NCX and nav parsing.
  - `DCEpubRendering`: SwiftUI and UIKit reader, plus the JS and CSS resources.
  - `DCEpubReaderKit`: re-exports the other modules.
- **Example app:** `Example/SwiftUI/Example.xcodeproj`. It uses Realm and ZIPFoundation and references the local package.
- **Rendering:** each chapter is XHTML shown in a `WKWebView`. Pagination uses CSS columns driven by `Resources/EpubUtil.js`, and highlights are stored as JS "coords" strings (node path plus character offset).

## Commits (oldest first)

| Commit | Summary |
| --- | --- |
| `41aded1` | Horizontal reader moved to `UIPageViewController` (curl or slide is a user setting). One `DCPageWebViewController` per page; vertical mode stays scrolling. |
| `e88686c` | Built-in JSON store (`DCJSONReaderStore`) for highlights, bookmarks and reading position, plus `DCStoreReaderDelegate`. |
| `4b4a0df` | Full-text search: `DCEpubSearchEngine` actor, `DCHTMLText`, and a search sheet. The match is highlighted in the page via JS `highlightSearchOccurrence`. |
| `c641b11` | Performance: a JS `waitForLayout()` readiness signal replaces fixed delays; page counts are cached; web views are recycled; neighbouring pages are preloaded. |
| `1e9efdc` | Example app fixes: the build failed with a missing package product; books with non-UUID ids showed a white screen (`FileHelper.bookDirectory`); Realm crashed with "Missing value for property bookId" (fixed with `internal import Realm` under MemberImportVisibility). |
| `5314288` | Apple Books-style reader: full-screen pages, page curl over the whole screen, floating Liquid Glass controls, ⋯ menu, Themes & Settings (6 presets plus Customize), Contents (TOC/Bookmarks/Highlights), Share, whole-book "N of M" via `DCBookPaginator`, and Line Guide (dim + outline by default, blur optional). |
| `bcf6522` | Theme switching recolors live pages via an injected `<style id="dc-theme">` instead of reloading. Only the Bold font weight repaginates. |
| `81e3425` | Page numbers stay visible (estimated from the last complete count) while the book is recounted. |
| `5917159` | The reading position is kept across consecutive relayouts. |
| `02a8e21` | Bookmarks: the button shows when the current page is bookmarked; tap again to remove. |
| `b2bdb9c` | Page numbers for Contents entries, bookmarks, highlights and search results. |
| `54f0983` | Controls hide while reading; tap the middle to show them; edge taps (20%) turn the page, like Books. |
| `469d43b` | Books-style selection menu with highlight colors (see below). |
| `071fd03` | Note editor: quotes the passage (bar in its highlight color), opens with the keyboard up, centered "Note" title with Done. Saves on close, so edits made within the 0.5 s debounce aren't lost. |
| `9e5f586` | Tap a highlight for a Books-style menu (recolor, Add/Edit Note, Copy, Share, Delete). Note marker icon after noted highlights. Highlights across paragraphs (see below). |
| `e3d2268` | Progress scrubber: drag to any page, with a chapter and "Page N of M" preview. Moves by chapter until the book is counted. |
| `67d426c` | "Back to Page N" after jumping (scrubber, Contents, marks, search, links). |
| `181e436` | Highlights list: filter chips (All, Notes, each color in use) and sort by page or date. Reading order compares coords numerically. |
| `8075832` | Customize → Text: line spacing, margins, Justify Text. Highlights no longer pad 2px past their text. |
| `bd1e649` | Footnotes in a popover; links inside the book jump with Back; web links open outside. Footnote asides are actually hidden now (see below). |
| `d76997a` | Add Note uses the last highlight color (yellow at first) instead of the red underline. |
| `88940e4` | Bug fixes: exact search result pages, scrolling-mode page counts, Share with the title, scrolling chapters resume after relayout. |
| `dff27ce` | Image viewer (tap a picture: pinch/double-tap zoom). Scrolling-mode jumps into earlier chapters open at their start. |
| `5f8712a` | Rotation lock (needs the host app delegate; see below). |
| `668a024` | Two-page spreads in landscape; Allow Multiple Columns; settings sheet scrolls on short screens. |
| `5ade87e` | Fixed-layout (pre-paginated) books: one designed page, scaled to fit. |
| `ebcdd90` | iOS fonts Books offers (Athelas … Seravek); character and word spacing. |
| `58deb2a` | Custom theme colors in Customize. |
| `4dbe278` | Overlapping highlights merge (notes kept). |
| `1d86764` | Note markers in the margin. |
| (this commit) | Share all highlights and notes from the Highlights list. |

In total, against `main`: 74 files changed, about 8.4k insertions. The last eight commits account for 38 files and about 2.2k of them.

## How the later features work

- **Highlights are tagged spans.** `wrapRange` in `EpubUtil.js` wraps each text node a highlight covers in its own `<span data-dc-highlight="<uuid>">` (the first also has the uuid as `id`). Elements are never moved, so a highlight can cross paragraphs. `setHighlightStyleById`, `setHighlightNoteById` and `removeHighlightById` act on every part. Removing calls `normalize()`, so later coords match a freshly loaded chapter. A selection overlapping another highlight is refused, because nested highlights would break coords.
  - Coords for a selection come from `normalizedSelectionRange`, which moves element boundaries into text nodes (WebKit puts them on elements when a selection crosses paragraphs).
  - `highlightCoords` returns early when the highlight is already drawn, so pages of a chapter can redraw each other's saves.
  - Selection granularity is `.character` in both readers. With the default, a dragged selection snapped to whole paragraphs and couldn't cross a paragraph break.
- **Keeping pages in sync.** Saving a highlight posts `.dcHighlightDidChange`. Every `DCWebView` redraws its color and note marker (`updateDrawnHighlight`).
- **Note marker:** `layoutNoteMarkers()` in `EpubUtil.js` draws `.dc-note-marker` divs in a layer on `<html>` (outside `<body>`, so no text, no line-break or coords changes), in the column gap (paged) or right margin (scrolling) beside the noted passage's last line. Relaid out after pagination and on note/highlight changes. Note `Style.css` has `div { max-width: 100% }`, so the marker needs `max-width: none`.
- **Merging:** `expandSelectionOverHighlights()` widens the selection over overlapped highlights using whole-body character offsets (node references don't survive unwrapping), removes them, and `saveSelection` deletes them from the store and joins their notes.
- **Export:** `DCMarksViewModel.exportText`, shared through `DCShareSheet` from the Highlights list; it follows the current filter and sort.
- **Taps on highlights and links:** `isTappableAtPoint` (JS) is checked by both readers' chrome-tap handlers, so these taps don't also toggle the controls or turn the page.
- **Links:** a capture-phase click listener in `EpubUtil.js` (`linkAction`) posts `linkTapped` messages:
  - `footnote`: a note in the same chapter, with its text. Shown in a popover by `DCWebView+Links.swift`.
  - `noteref`: a note in another file. Read in Swift by `DCFootnoteText` (an XMLParser in `DCEpubCore`).
  - `link`: anywhere else. Goes through the router to `DCChapterViewAction.openLink` and then `DCReaderViewModel.openLink`, which uses `DCEpubBook.spineIndex(forChapterURL:)`.

  The chapter's own URL is injected as `window.dcChapterURL`, because the page's base URL is only its folder.
- **Footnote CSS:** chapters are loaded with `loadHTMLString`, so they're parsed as HTML, where `epub:type` is a plain attribute name. The old `aside[epub|type~=footnote]` rule never matched (it also lacked an `@namespace`). The escaped `aside[epub\:type~="footnote"]` is the one that works.
- **Back:** `DCReaderViewModel.backPosition` is recorded by `rememberPositionBeforeJump()` before every jump, using saved coords when known so it survives a relayout. There's one level of back, with no forward.
- **Scrubber:** `DCReaderViewModel.scrubTarget(fraction:counts:chapterCount:)` maps 0…1 to a chapter and page. Jumps go through `DCPagedReaderNavigating.show(spineIndex:page:)`, or the new `DCChapterJump.page` in scrolling mode.
- **Text layout:** `DCTextLayout` (line spacing, margins, justified) is stored under the `lineSpacing`, `pageMargins` and `justifyText` keys. CSS is injected as `<style id="dc-layout">`, and margins are native insets. `textLayout.id` is part of `pagedConfigId`, `readerConfigId` and the paginator's style id, so a change lays the book out and recounts.
- **Image viewer:** `imageAction` in `EpubUtil.js` posts `{kind: 'image'}` for a tapped `<img>`/SVG `<image>` that isn't in a link; `DCImageViewerController` shows it.
- **Rotation lock:** iOS asks the app delegate, so the host returns `DCReaderOrientationLock.supportedOrientations` from `application(_:supportedInterfaceOrientationsFor:)`. The example app's `AppDelegate.swift` does (it's listed in the Xcode project by hand). The reader unlocks when it closes.
- **Spreads:** `columnsPerPage()` in `EpubUtil.js` is 2 on wide landscape pages when `window.dcAllowSpreads`; 2n columns fill n pages, so pages are still `innerWidth` apart and nothing else changes. Line Guide reads column by column.
- **Fixed layout:** `DCEpubBook.isFixedLayout(spineIndex:)` (package `rendition:layout`, overridable per itemref). `DCChapterHTMLBuilder` loads those pages without the reader stylesheet, with `window.dcFixedLayout` set to the viewport size; `applyFixedLayout` scales and centers them, and the pagination functions return 1.
- **Fonts:** system fonts are CSS classes on `<html>` like the bundled ones (`DCFontFamily.systemFontStack` and `Style.css` must agree; a test checks).
- **Theme colors:** `DCThemeColorStore` (UserDefaults `DCThemeColors`, keyed `theme-light|dark`). `DCReaderAppearance` now carries the resolved colors; use `hasDarkBackground` rather than `isDark` for contrast decisions.
- **Last highlight color:** `DCHighlightStyle.lastUsed` (UserDefaults key `DCLastHighlightStyle`).
- **Search result pages** are exact: after each search, `DCBookPaginator.locateSearch` lays out each matching chapter off screen and runs `highlightSearchOccurrence` for every match, the same code the reader jumps with. The sheet shows the estimate until then.
- **Scrolling mode:**
  - `applyVerticalPagination` returns the number of screens a chapter takes, so the whole-book count and "N of M" work.
  - A chapter that reloads after a layout change resumes at the last reported position.
  - Jumps into a neighbouring chapter that's already loaded run straight away. Before, they waited for a load that never came, so they landed at the chapter's top.
- **Back label:** after a relayout, "Back to Page N" names the chapter instead, because the saved page number belongs to the old layout.
- **Sharing a passage** (selection or highlight menu) sends the same text as ⋯ → Share: the quote, then "Title by Author" (`DCEpubBook.shareText(quoting:)`).

## Selection menu (`469d43b`)

- **Menu:** `DCWebView.buildMenu(with:)` replaces the system edit menu (the old `UIMenuController` code is gone) with:
  - a palette of swatches (yellow, green, blue, pink, purple, underline), image-only with accessibility labels;
  - Add Note;
  - Look Up and Translate (the system's commands, minus web search);
  - Search, which opens the book search with the selection via `searchBook(for:)` → `DCChapterViewAction.searchBook`;
  - Copy;
  - Share….
- **Model:** `DCHighlightStyle` enum; `DCHighlight.style` is optional so old data decodes; `displayStyle` provides the fallback.
- **Styling:** CSS class `highlight-<style>`, and purple was added to `Style.css`.
- **Persistence:** the example's Realm `RBookMark.style` was added and the schema bumped to 2.
- **Highlights list:** icons are tinted with the highlight color.
- **Long press:** no longer also toggles the controls (a long-press recognizer the tap must fail).
- **JS fixes in `EpubUtil.js`:**
  - `isHighlightElement`/`isHighlightClassName` recognise every highlight color. Previously only yellow and underline were recognised, so other colors became the blue search style.
  - `getNodeFromCoordFix` now skips the doctype, matching how coords are generated. XHTML chapters have `<?xml?>` and `<!DOCTYPE>` before `<html>`, so the second and later marks in a paragraph redrew on the wrong words or vanished. This bug predates the branch.

## Testing

- Uses Swift Testing (116 tests). WebKit-backed suites are nested under `WebKitBackedTests` (in `DCSearchHighlightJSTests.swift`), which runs serially.
- Run via `xcodebuild`, because Xcode's in-memory file list can be stale for new files:

  ```sh
  xcodebuild test -scheme DCEpubReaderKit \
    -destination 'platform=iOS Simulator,id=<booted sim id>' \
    -derivedDataPath /tmp/dcepub-ui-dd \
    -test-timeouts-enabled YES -maximum-test-execution-time-allowance 120
  ```

  The iPhone 17 (iOS 27.2) simulator sometimes fails to boot. Using an already-booted simulator by id works.
- `WKWebView` snapshots are blank in the test runner (no host app), so check the blur line focus in the app.
- WebKit test pages need `<meta name='viewport' content='width=device-width'>`. Without it the page lays out at 980 px wide, and pagination tests don't paginate.
- Simulator screenshots taken at `scale: 0.3` are 920×2000 for a 402×874-point screen: divide by about 2.29 to get tap points.
- In the simulator, taps from the control tool can be too short to flip a SwiftUI `Toggle`. A two-point touch path with about 120 ms between points works.
- Build and run the example app:

  ```sh
  xcodebuild build -project Example/SwiftUI/Example.xcodeproj -scheme Example \
    -destination 'platform=iOS Simulator,id=<sim id>' -derivedDataPath /tmp/dcex-ui-dd
  xcrun simctl install <sim id> /tmp/dcex-ui-dd/Build/Products/Debug-iphonesimulator/Example.app
  xcrun simctl launch <sim id> com.example.Example
  ```

- Test books: "Fundamental Accessibility Tests: Basic Functionality" (EPUB 3), and "Fixed Layout Test", a two-page pre-paginated book built for testing (imported into the simulator from Files → Downloads). It has internal links (the supplement's "return to the search feature test") but no footnotes. To see a footnote, add a temporary `noteref` and `aside` to the app's copy of `supplement.xhtml`, then restore it.

## Conventions

- Commit each feature as soon as it is built and its tests pass, one commit per feature, on `feature/roadmap-items`. Don't push unless asked.
- End commit messages with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Prefer async/await over Combine. Use Swift Testing for unit tests.
- In the example app, files that create Realm objects need `internal import Realm`.
- The shell is zsh: `$VAR` holding a list of paths isn't split into words. Spell out the paths in `git add`/`git commit`.
- Leave `WORK_LOG.md` and `MISSING_FEATURES.md` out of feature commits unless asked.

## Known issues and ideas for next steps

- Hidden controls may still be in the accessibility tree.
- Overlapping highlights are refused, not merged.
- The note icon sits inline after the highlight. It can shift a paragraph's line breaks slightly, and the highlight color (or underline) runs under it.
- Footnotes from a separate endnotes file and web links are covered by tests but haven't been tried in the app.
- Next from `MISSING_FEATURES.md`: merging overlapping highlights, the image viewer, two-page spreads, and read aloud.
