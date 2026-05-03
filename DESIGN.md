# Current Design System

Current is a native macOS daily-stream Markdown editor. Its interface should feel like a warm sheet of paper with just enough structure to help capture, find, and move through time. The design goal is not a full document suite, an IDE, or a decorated notes dashboard. The goal is fast, calm daily writing with transparent plain-text storage.

This document is implementation-ready guidance for future visual work. It does not define new app behavior, public APIs, or data models.

## Product Intent

Current exists for quick capture and continuous review:

- Open the app and immediately write.
- Keep today's note visually primary.
- Keep previous days available without making the screen feel busy.
- Preserve Markdown as plain text, with syntax highlighting as a reading aid.
- Make files, native find, and timestamps available through quiet native controls.
- Avoid UI that asks the user to manage layout before they can write.

The app should feel native, focused, warm, and light. Chrome should be useful but easy to forget. Structure should come from spacing, typography, and hairline dividers, not heavy cards or panels.

## Visual Principles

- **Warm paper first:** the default light mode is white and warm-neutral, closer to paper than plastic.
- **Capture over composition:** Current is for daily stream writing. Do not add document-design controls that compete with typing.
- **One continuous stream:** day sections are the primary organizing structure. Avoid permanent surfaces that fragment the timeline.
- **Whisper-weight structure:** use 1px dividers, low-opacity fills, and small typographic shifts instead of heavy borders.
- **Native restraint:** prefer system materials, system icons, and AppKit text behavior. Custom styling should clarify, not decorate.
- **No clunky chrome:** no large toolbar blocks, nested cards, loud gradients, oversized labels, or persistent panels that make writing feel secondary.

## Color Tokens

Implement tokens in `CurrentTheme` first, then consume them from `ContentView`, `MarkdownEditorView`, and `MarkdownSyntaxHighlighter`.

### Light Mode

| Token | Value | Use |
| --- | --- | --- |
| `pageBackground` | `#FFFFFF` | Main editor canvas and scroll background |
| `appSurface` | `#F6F5F4` | Subtle app chrome, empty historical space, optional future side surfaces |
| `chromeBackground` | `rgba(246,245,244,0.82)` | Top and bottom bars, using material when appropriate |
| `editorBackground` | `#FFFFFF` | `NSTextView` background |
| `primaryText` | `rgba(0,0,0,0.92)` | Editor text, strong labels, active icons |
| `secondaryText` | `#615D59` | Stream name, day labels, metadata |
| `mutedText` | `#A39E98` | Placeholders, inactive historical labels, subtle counts |
| `divider` | `rgba(0,0,0,0.10)` | Day rules, chrome separators |
| `softDivider` | `rgba(0,0,0,0.06)` | Internal lines and low-emphasis separators |
| `fieldBackground` | `rgba(0,0,0,0.035)` | Search field and quiet icon hover state |
| `fieldBackgroundActive` | `rgba(0,0,0,0.055)` | Search field when focused or populated |
| `accent` | `#0075DE` | Focus rings, links, selected search hit, rare primary action |
| `accentSoft` | `#F2F9FF` | Search hit background and gentle status tint |

### Dark Mode

Dark mode is a companion, not the primary visual target. It should remain warm and quiet rather than high-contrast black.

| Token | Value | Use |
| --- | --- | --- |
| `pageBackground` | `#1F1E1C` | Main editor canvas |
| `appSurface` | `#252321` | Chrome and optional future side surfaces |
| `chromeBackground` | `rgba(37,35,33,0.86)` | Top and bottom bars |
| `editorBackground` | `#1F1E1C` | `NSTextView` background |
| `primaryText` | `rgba(255,255,255,0.88)` | Editor text and active icons |
| `secondaryText` | `rgba(236,232,226,0.64)` | Day labels and metadata |
| `mutedText` | `rgba(236,232,226,0.42)` | Placeholders and inactive metadata |
| `divider` | `rgba(255,255,255,0.10)` | Day rules and chrome separators |
| `softDivider` | `rgba(255,255,255,0.07)` | Internal lines |
| `fieldBackground` | `rgba(255,255,255,0.055)` | Search and hover fills |
| `fieldBackgroundActive` | `rgba(255,255,255,0.085)` | Focused or populated search |
| `accent` | `#62AEF0` | Focus rings, links, selected search hit |
| `accentSoft` | `rgba(98,174,240,0.14)` | Search hit background |

### Depth

Current should mostly feel flat. Use depth only where the system already expects it.

- Editor canvas: no shadow, no border.
- Bottom chrome: material or translucent fill plus a 1px separator.
- Day sections: no card background by default.
- Search hit: soft tinted rounded rectangle, max radius 8px.
- Menus, popovers, and future sheets: system elevation is enough.
- Avoid custom shadow stacks in the main editor. If a future modal needs depth, use a low-opacity native-style shadow and keep it outside the writing stream.

## Typography

Current uses two type systems: monospaced editor text for capture and system sans for chrome.

### Editor

| Token | Value |
| --- | --- |
| Font | `.monospacedSystemFont` |
| Size | `13px` |
| Weight | regular |
| Line height | `21px` to `22px` |
| Baseline offset | Center text optically in the line box |
| Horizontal inset | `0px` inside the text view, with outer column padding controlled by the timeline |
| Vertical inset | `8px` |

Guidance:

- Keep editor text monospaced. It reinforces plain text, Markdown, timestamps, lists, and paste-heavy capture.
- Increase from the current 12px feel to 13px for calmer reading.
- Use line height to create breathing room rather than increasing paragraph margins in `NSTextView`.
- Preserve fast typing and native selection behavior. Typography changes must not create cursor jumps or layout churn.

### Markdown Syntax

Syntax highlighting should clarify structure without turning notes into colorful code.

| Element | Treatment |
| --- | --- |
| Body text | `primaryText`, editor regular font |
| Markdown markers | `mutedText` or `secondaryText` at reduced emphasis |
| Headings | editor font at 14px, semibold, `primaryText` |
| Bold | editor font semibold |
| Italic | slight obliqueness, not a separate decorative font |
| Links | `accent`, no heavy underline while editing |
| Blockquotes | `secondaryText`, optional muted marker |
| Inline code | editor font, `secondaryText`, soft background no stronger than 6 percent black or 8 percent white |
| Fenced code | editor font, `secondaryText`, no boxed card surface in edit mode |
| Checkboxes and list markers | marker muted, content primary |

Headings should be subtly stronger, not oversized. The editor should still feel like one plain-text stream.

### Chrome

| Role | Size | Weight | Color |
| --- | --- | --- | --- |
| Stream label | 11px | medium | `secondaryText` |
| Search field | 12px | regular | `primaryText` |
| Icon buttons | 14px to 15px symbol | regular or medium | `secondaryText` |
| Day label | 11px | semibold | `secondaryText` |
| Day label tracking | `0.6px` to `0.8px` | uppercase | `secondaryText` |
| Bottom metadata | 10px | regular | `mutedText` |
| Tiny action label | 10px | medium | `secondaryText` |

Use the system sans font for all chrome. Keep labels compact, stable, and easy to scan.

## Layout

### Window

- Minimum window remains close to `820 x 640`.
- The main scroll area fills available space.
- The writing column remains centered.
- Default content max width should be `680px` to `720px`.
- Horizontal scroll padding should be generous: `56px` on standard desktop widths.
- Avoid full-width text. The app should feel spacious even when the window is wide.

### Timeline

The timeline is the core layout model.

- Today appears first and should be expanded by default.
- Historical days with content may expand, but collapsed days should remain lightweight.
- Empty recent days may stay collapsed and scannable.
- Older history loads in small in-memory batches as the user scrolls.
- Empty placeholder days are a bounded runway, not an infinite calendar.
- Day sections use vertical padding, not card chrome, to separate entries.
- The day divider is a label plus a hairline that extends across the writing column.
- Older days load automatically as the user scrolls toward the end of loaded history.
- Search hit highlighting can softly tint the day section, but should not create a card-like block.

### Editor Surface

- The editor has no visible container.
- The text view background matches `editorBackground`.
- Placeholder text uses `mutedText`.
- Today's empty editor should have a generous minimum height, around `280px`.
- Non-empty historical editors should use content-driven height with a small minimum, around `64px`.
- Avoid internal scrollbars inside each day editor. The outer timeline scroll owns vertical movement.

## Components

### No Persistent Top Bar

Implementation home: `ContentView.body`.

- The default capture surface has no top toolbar.
- The first visible app content should be whitespace, the current day divider, and the editor.
- Use native menus and keyboard shortcuts for jump to today, insert timestamp, reveal files, and find.
- A future stream switcher or expanded search may temporarily occupy the titlebar, but it should not return as permanent chrome in MVP 0.

### Day Divider

Implementation home: `DaySectionView.dayDivider`.

- Label text is uppercase, semibold, tracked, and compact.
- Today label format remains `TODAY · WED, APR 29` style.
- Historical labels omit "Today".
- Divider line uses `softDivider`.
- The active day divider shows a tiny save-state orb after the date label: muted when saved, soft accent while saving.
- Button target should span the full divider row.
- Collapsing/expanding animation should stay quick, around `0.18s`.

### Editor

Implementation homes: `MarkdownEditorView` and `MarkdownSyntaxHighlighter`.

- Use an AppKit `NSTextView`.
- Preserve native undo, find panel behavior, paste behavior, and keyboard editing.
- Use `CurrentTheme.editorFont`, `editorLineHeight`, and `editorBaselineOffset`.
- Use `CurrentTheme.editorBackground` for the text view background.
- Keep text container line fragment padding at `0`.
- Do not wrap the text view in a card, panel, or bordered surface.
- Keep syntax highlighting incremental and low-contrast.

### No Persistent Bottom Bar

Implementation home: `ContentView.body`.

- The default capture view does not show a persistent bottom bar.
- File reveal lives in the Stream menu and keyboard shortcut.
- Save state belongs to the active day divider, not a separate chrome strip.

### History Loading

Implementation home: `HistoryLoaderView`.

- Do not show a persistent "load older" button in the default stream.
- Load one small batch of older in-memory days as the user scrolls toward the end of loaded history.
- Do not create Markdown files for blank days while scrolling.
- Stop adding blank placeholder dates after the configured runway, then load only older real `.md` files.
- Disable the invisible loading trigger when there is no older blank runway or real note file left.
- The trigger may prefill a few bounded batches while its spacer is still visible so short collapsed rows do not stall the scroll.
- The loading trigger should be invisible and must never chain beyond the bounded history runway or available real files.
- Keep today's day and dirty days pinned through the cache behavior.

## Future Surfaces

Future roadmap items should extend the design system without turning Current into a heavy workspace shell.

### Multiple Streams

- Stream switching should use a compact popover or native menu first.
- A persistent sidebar is allowed only when it can be hidden easily and does not reduce the writing column below the target width.
- Side surfaces use `appSurface`, not a saturated color.

### Search Across History

- Expanded search may use a command-style overlay or popover.
- Results should be dense, text-first, and date-grouped.
- Avoid preview cards. Use snippets and day labels.

### Calendar Picker

- Calendar navigation should feel like a lightweight date affordance.
- Avoid a permanent calendar panel in the default capture view.

### Preview and Export

- Preview should be optional and mode-based.
- Do not introduce a permanent split preview by default.
- Rendered Markdown can use proportional reading typography, but edit mode remains monospaced.

### AI Review

- AI features must be opt-in and quiet.
- Suggestions should appear as review surfaces, not inline surprise rewrites.
- Any writeback should require user approval.

## Implementation Path

1. Expand `CurrentTheme` into semantic light and dark tokens for page, chrome, editor, text, dividers, fields, and accent.
2. Update editor typography tokens to 13px with 21px to 22px line height.
3. Update `ContentView` to consume semantic chrome, search, divider, and text tokens instead of raw opacity values.
4. Tune `MarkdownSyntaxHighlighter` to use semantic syntax colors and reduce contrast on Markdown markers.
5. Verify the live app in light mode first, then dark mode.
6. Keep behavior unchanged unless a visual issue reveals an interaction bug.

## Acceptance Checklist

- The app opens to a calm writing surface with today's editor visually primary.
- Light mode feels warm and paper-like, not cold gray.
- Dark mode feels warm charcoal, not pure black.
- No top bar appears in the default capture view.
- No persistent bottom bar appears in the default capture view.
- Day dividers are scannable and remain the main timeline structure.
- Editor text is easier to read than the current 12px baseline.
- Syntax highlighting clarifies Markdown without becoming colorful or busy.
- No major surface looks like a nested card.
- Icon buttons remain stable in size and have help text.
- The writing column remains centered and readable at narrow and wide window sizes.

## Anti-Patterns

- Do not add nested cards inside the timeline.
- Do not use heavy borders, high-opacity separators, or visible panel outlines around the editor.
- Do not add large toolbar buttons with text labels to the default capture view.
- Do not introduce saturated multi-color syntax highlighting.
- Do not use decorative gradients, blobs, or illustration backgrounds.
- Do not make search, preview, AI, or future sidebars compete with the daily stream.
- Do not replace native text editing behavior for visual polish.
- Do not hide plain Markdown syntax in edit mode.

## File Ownership

This design system currently maps to these implementation areas:

- `CurrentTheme`: semantic tokens, colors, typography, spacing, and editor metrics.
- `ContentView`: app shell, timeline, day sections, and history loading trigger.
- `MarkdownEditorView`: AppKit text view behavior, editor background, insets, cursor, height measurement, and focus.
- `MarkdownSyntaxHighlighter`: Markdown token styling, line height, heading emphasis, list indentation, and inline code treatment.

Keep design constants centralized in `CurrentTheme` whenever possible. View files should read like composition, not a collection of one-off style decisions.
