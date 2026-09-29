# Current: writing surface polish

The daily stream remains the primary document. Standalone notes remain a later extension. This pass keeps native AppKit editing and local Markdown storage.

## Composition

Use a centered 640-point column, 16-point system body text at 25.6-point line height, 26-point H1 and 21-point H2. The writing surface starts 8 points below its content boundary. Dates use 12-point type without full-width rules. Empty Today starts as a compact editable line. Historical empty runs become one disclosure row; a calendar jump can always open an empty date.

Navigation uses a real `NavigationSplitView` and a `List` with sidebar styling. The system supplies row sizing, selection, disclosure controls, typography and materials. Observe the resized sidebar's geometry to persist its width between 200 and 320 points; restore that width as the initial column preference. Keep native keyboard focus visible.

The writing palette remains independent of navigation chrome. Light: paper #FFFFFF, text #242426, secondary #67676B, divider #E6E6E9, accent #456F98. Dark: paper #1E1E20, text #F1F1F3, secondary #B0B0B5, divider #3A3A3E, accent #97B8D9. Sidebar and toolbar materials follow the operating system and selected appearance, without copied styles or custom glass wrappers.

A unified native window toolbar hides the app title and groups the stream switcher, date actions, search, creation and view options. Standard components adopt the system's modern appearance automatically. macOS 26 toolbar spacers and the native glass exit button are availability guarded; macOS 14 retains native toolbar spacing and a bordered exit button.

Ordinary stream selection replaces the current document. Tabs are explicit and off by default. Their accessory strip uses native selection controls with separate, lightweight close or pin buttons and supports reordering. Focus mode switches the split view to detail only and hides the native toolbar and tabs, keeping a small exit control over the writing surface. Sidebar visibility and tab preferences survive focus mode.

## Interaction details

- Daily uses a calendar; other streams use a notebook; creation uses plus.
- A collapsed populated day retains a readable excerpt beside its date and disclosure.
- The calendar marks written days, distinguishes Today from selection, and opens dates directly.
- Search shows plain-text, query-centered excerpts with highlighted matches while keeping exact source offsets for selection.
- The switcher includes folder context and offers creation for an unmatched name.
- Short tables fit their content. Wide tables allocate width to columns according to content and wrap within the writing measure.
- A single inactive blank separator after a heading renders at 6 points; active writing, repeated/trailing blank lines, code and source mode keep normal geometry.
- Existing-stream `[[name]]` links complete through native input and undo. Ambiguous names remain literal; folder-qualified names can disambiguate. Code never activates stream links.
- Motion is confined to subtle control feedback. Text layout, caret movement, row resizing and scroll anchoring are never animated. Reduce Motion is respected.

## Reference decisions

[Apple's SwiftUI design guidance](https://developer.apple.com/videos/play/wwdc2025/323/) informs the native split view, sidebar and automatic system materials. [Apple's window toolbar API](https://developer.apple.com/documentation/swiftui/windowtoolbarstyle) supplies unified window chrome. Navigation follows these platform components rather than a copied web stylesheet.

[Impeccable](https://impeccable.style/designing/) informs task-led hierarchy and difficult-state review. [Transitions](https://transitions.dev/) informs small, purposeful feedback. [Bear typography](https://bear.app/faq/typography-options/) and [iA Writer settings](https://ia.net/writer/support/basics/settings) inform reading measure. [Flo State specification](https://github.com/Altimor/flo-state/blob/main/docs/SPEC.md) informs selection stability; implementation is independent.

## Verification

Compare live paragraph/glyph layout after rapid paste, typing, deleting and undo with a fresh editor. Exercise headings, lists, code, mixed Unicode, source switching, resize and appearance changes. Check canonical text and disk bytes, not only screenshots. Exercise more than 1,000 lines and repeated history-window transitions with bounded editor caches. Review real native windows in dark, light and narrow layouts with realistic rough notes. Check tab intent, focus restoration, search selection, empty dates, calendar markers, keyboard input, save failures and recovery. Record observed limits; no claim of zero possible bugs or measured frame-rate parity.

The native shell passes 107 package tests, storage checks, 29 normal native checks, 29 combined long-note/history checks, and five narrow-window checks. The actual app was reviewed in both appearances, including sidebar keyboard selection, optional tabs, calendar presentation, and focus-mode entry and exit. Sidebar width restoration uses a fresh workspace instance. Height changes with the sidebar hidden preserve the long note's caret, typing and undo. See [the validation record](revamp-validation.md) for measurements and test limits. Availability guards compile for macOS 14; runtime review was on macOS 26.

The subsequent restraint pass removes the website's decorative gradients, blurred header, icon shadow, faded editor backdrop, duplicated labels and numbered future-feature section. A readable note example now stays in normal flow at narrow widths. App-authored surfaces had no decorative gradients or shadows; native macOS materials remain intact. Short stream and command lists now use content-sized result areas, with long lists bounded and scrollable. The no-gradients preference is recorded in `AGENTS.md` and `DESIGN.md`.

Validation for that pass: the website production export and TypeScript checks pass; desktop and 390-point home/settings layouts were reviewed with no horizontal page overflow. All 107 app tests and storage checks pass. The release app's switcher was checked with a single creation result, a full stream list, arrow keys, and Return back to Payments. No test stream was created, and all ten preview Markdown files remained byte-for-byte unchanged.

The stream control now combines the breadcrumb with one native toolbar menu pill. Its system dropdown lists sibling streams, marks the current stream, and includes “Switch Stream…” for the full picker; ⌘O still opens that picker directly. The label uses a single composed Text value because the native toolbar extracts only the first text/image from a compound HStack menu label. Real-app review confirms the full path and menu-to-picker action. The package suite still passes 107 tests plus storage checks, and the 820 × 640 native window passes five layout checks.

The in-process probe cannot expose that native menu on this system, so it explicitly records the stream-creation interaction as skipped when no menu action is accessible. This is not counted as a passing interaction. The menu and its “Switch Stream…” action were verified through external accessibility in the release app; the full normal-workspace probe is not claimed to pass for this follow-up.
