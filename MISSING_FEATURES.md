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
- **Appearance:** six theme presets with Customize (font, size, Bold, line spacing, margins, justification), matching system dark mode, and brightness.
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
| P2 | Two-page spread in landscape and on iPad | Books shows two columns side by side. |
| P2 | Image viewer | Tap an image to view it full screen with zoom. |
| P3 | Rotation lock and orientation handling | A reader setting in Books. |
| P3 | Fixed-layout EPUB support | Comics and picture books (pre-paginated). Only reflowable books are supported. |

## Text and layout settings (Customize)

We have: font family (original, Andada, Lato, Lora, Raleway), 8 text sizes, Bold, line spacing, margins, justification, and page-turn style.

| Priority | Feature | Notes |
| --- | --- | --- |
| P2 | Character and word spacing | Accessibility options in Books. |
| P2 | Allow multiple columns | Books toggles columns in landscape and on iPad. |
| P2 | More fonts | Books ships Athelas, Charter, Georgia, Iowan, New York, Palatino, San Francisco and others. The system fonts could be offered. |
| P3 | Custom theme colors | Books lets you edit a theme's background and text colors. |

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
