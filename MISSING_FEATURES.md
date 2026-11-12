# Apple Books features still missing

Apple Books EPUB reader features that DCEpubReaderKit doesn't have yet, as of `d76997a` on `feature/roadmap-items`. See `WORK_LOG.md` for what's already built.

Priority: **P1** = most noticeable when compared side by side with Books, **P2** = nice to have, **P3** = larger or niche.

## Already done (for reference)

These exist and are not missing:

- **Reading and navigation:**
  - Page curl and slide turns, plus a scrolling mode.
  - Full-screen pages with controls that hide while reading.
  - Edge taps to turn pages.
  - Whole-book "N of M" page numbers.
  - Contents, Bookmarks and Highlights in one sheet, with page numbers.
  - "Pages left in chapter" at the top.
  - Progress scrubber with a chapter preview, and "Back to Page N" after any jump.
  - Footnotes in a popover; internal links jump with Back.
- **Highlights and notes:**
  - Tap a highlight for its menu (recolor, Add/Edit Note, Copy, Share, Delete).
  - Highlights across paragraphs.
  - Note marker in the text.
  - Notes take the last highlight color.
  - Note editor quotes the passage and opens with the keyboard up.
  - Highlights list filters (color, notes) and sort (page, date).
- **More reading:** image viewer (tap a picture to zoom), rotation lock, two-page spreads in landscape, fixed-layout (pre-paginated) books.
- **Appearance:** six theme presets with Customize: 13 fonts (including the iOS ones Books uses), size, Bold, line spacing, character and word spacing, margins, justification, multiple columns, and custom theme colors; matching system dark mode, and brightness.
- **Line Guide:** dim-and-outline style or blur.
- **Search and sharing:** book search, and Share.
- **Selection menu:** colors, Add Note, Look Up, Translate, Search, Copy, Share.

## Highlights and notes

| Priority | Feature | Notes |
| --- | --- | --- |
| P2 | Merge overlapping highlights | Highlighting text that overlaps an existing highlight should extend or merge it. Today the selection is refused. |
| P2 | Note marker in the margin | Ours is an inline icon after the highlight. Books puts it in the margin, which wouldn't affect line breaks. |
| P3 | Export or share all highlights and notes | Books can share or export a book's annotations. |

## Reading experience

| Priority | Feature | Notes |
| --- | --- | --- |
| P3 | Fixed-layout spreads | Two fixed-layout pages side by side in landscape (`page-spread-left/right` are parsed but unused). |

## Text and layout settings (Customize)

All of Books' Customize options are in.

| Priority | Feature | Notes |
| --- | --- | --- |

## Audio and accessibility

| Priority | Feature | Notes |
| --- | --- | --- |
| P2 | Read aloud / Speak Screen | Books follows along as text is spoken. The CSS has an `epub-media-overlay-playing` class, but nothing drives it yet. |
| P2 | EPUB 3 media overlays | Synced narration in books that include audio. |
| P2 | VoiceOver page reading | Continuous reading across page turns; the hidden controls may still be in the accessibility tree. |
| P3 | Dynamic Type for text size | Optionally follow the system text size. |

## Library and sync (mostly the host app's job)

| Priority | Feature | Notes |
| --- | --- | --- |
| P3 | iCloud sync | Reading position, highlights, notes and bookmarks across devices. The store protocols allow a custom backend. |
| P3 | Reading goals and streaks | Time read and daily goals. |
| P3 | Collections, Want to Read and Finished states | Library organisation in the example app. |

## Known bugs to fix first

None known. Search result page numbers, scrolling-mode page counts and Share from a selection were fixed after `d76997a`.
