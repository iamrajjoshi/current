# Current writing workspace

Current is a local Markdown workspace centered on daily streams. Open the app, write in today's note, switch context when needed, and find older writing without managing individual files. Standalone notes come later.

## Structure

The hierarchy is Library → Folder → Stream → Day. Folders group streams in metadata; moving a stream between folders doesn't move its files. Each stream presents a today-first daily timeline. Tabs are off by default. Ordinary sidebar and picker selection replaces the current stream; only Open in Tab adds a tab. Explicit tabs remain open when the current stream changes.

The window uses a native `NavigationSplitView`, a sidebar-styled `List`, and one continuous writing surface with an 8-point top inset. Pinned streams, folders and archive use native rows, selection and disclosure controls. The sidebar is resizable and collapsible, with persisted preferences. A unified native window toolbar hides the app title and provides the stream switcher, Today, a calendar with writing indicators, search, stream creation and view options. There is no persistent footer, calendar rail, or split preview.

Show the current location as a breadcrumb inside one native toolbar menu pill: `Work › Payments`, or `Library › Daily` for ungrouped streams. The menu lists sibling streams and offers “Switch Stream…” for the full picker; ⌘O remains the direct shortcut. Use the system dropdown indicator, a quiet path separator and bounded labels that prioritize the current stream. The path follows folder moves and renames. Let macOS draw the shared toolbar background, without a custom capsule or material.

Optional tabs occupy an accessory strip with native selection controls and separate close or pin actions. They support explicit reordering. Closing a tab doesn't archive its stream; closing the last explicit tab hides the strip. Focus mode switches the split view to detail only and hides the native window toolbar and tabs, retaining a small exit button and preserving ordinary view preferences. The timeline and native editors stay in the same detail hierarchy.

Small date labels and disclosure chevrons separate days. Collapsed populated days show a clean excerpt. Empty historical runs fold into a compact date-range row and remain accessible by disclosure or calendar. Don't put cards around notes.

## Color and typography

No decorative gradients, glows, simulated glass, or ornamental shadows in app-authored UI or the website. Use solid surfaces and deliberate spacing. Native macOS materials remain system-owned. Labels should help a person act or understand content; remove duplicate headings, promotional empty states, and decorative numbering. Product examples should contain realistic working notes.

Use semantic tokens in `CurrentTheme` for the writing surface. A muted blue accent distinguishes content links and selection. Navigation uses system typography, intrinsic control sizing, selection and materials; don't paint custom sidebar backgrounds or wrap standard toolbar controls in simulated glass. Appearance follows the system unless the user chooses light or dark. Native keyboard focus remains visible. Control feedback respects Reduce Motion; editing geometry never animates.

| Token | Light | Dark |
| --- | --- | --- |
| Canvas | `#FFFFFF` | `#1E1E20` |
| Primary text | `#242426` | `#F1F1F3` |
| Secondary text | `#67676B` | `#B0B0B5` |
| Muted text | `#737378` | `#A1A1A8` |
| Divider | `#E6E6E9` | `#3A3A3E` |
| Accent | `#456F98` | `#97B8D9` |

Body text defaults to a 16-point proportional system font with a 25.6-point line box. Explicit user font settings remain supported. Code uses a monospaced font. Major headings are 26 points, second-level headings 21, and smaller headings 18 by default. Dates use 12-point type; sidebar labels and rows follow the system.

A single complete blank separator after a heading uses a 6-point display line while inactive. The active writing line, trailing blank lines, repeated blank lines, source mode and code retain their normal height. This tightens the reading gap without rewriting Markdown or changing intentional paragraph spacing.

The default window is 1180 × 820 points; minimum content size is 820 × 560, plus the native titlebar. The sidebar can resize between 200 and 320 points. Persist its observed geometry and restore the saved width as the initial split-view preference; let the system determine row heights and group spacing. The centered writing column has a configurable 640-point maximum and 32-point outer padding where space allows. Empty editors have a 48-point minimum and grow from measured content. The outer timeline owns vertical scrolling and respects the native window's content boundary.

Standard navigation and toolbar components adopt macOS 26 system materials automatically. Guard macOS 26 toolbar spacers and the focus exit button's native glass style by availability, retaining native toolbar spacing and a bordered exit control on macOS 14. [Apple's SwiftUI design guidance](https://developer.apple.com/videos/play/wwdc2025/323/) and [window toolbar API](https://developer.apple.com/documentation/swiftui/windowtoolbarstyle) are the reference for this chrome. Don't apply content-extension effects or additional glass surfaces to the live TextKit document.

## Markdown presentation

Markdown source remains canonical. Display attributes, syntax hiding, checkbox clicks, appearance changes, and layout never silently rewrite source.

Inactive content renders cleanly. Headings hide their prefixes; tasks use native checkbox decorations; quotes have a quiet side rule; code uses a subdued background; rules use one hairline. Tables and local images render in place. The active logical line or rich block reveals source for editing. Markdown Source exposes the complete text while preserving the document, selection, and undo stack.

Incomplete or unsupported syntax stays readable. Rich-content failures return to source. No speculative network loads are needed to display local images. Attachments are stored relative to the note's stream and inserted through undoable edits. Short tables fit their contents; long columns receive additional available width and wrap. Measurement and drawing share column offsets, widths and row heights.

`[[stream]]` links resolve existing, unambiguous streams; folder-qualified names distinguish duplicate destinations. Native completion preserves undo and leaves source unchanged while previewing or cancelling. Unresolved names and syntax inside code remain literal. Link coloring and muted brackets preserve character geometry.

Native input owns composition, selections, spelling, undo, find, and clipboard behavior. Freeze geometry-changing syntax reveal during a selection drag and suspend it during marked text composition. Don't animate text reflow or caret/scroll correction.

## Rendering architecture

Each text storage revision owns a cached source-range render model. The block scanner handles fenced regions in one pass, including unclosed and tilde fences. Inline processing respects protected code regions. Dirty regions combine old and new block boundaries so deleting a delimiter clears stale formatting downstream.

A detached attributed source caches rendering plans for logical lines and complete fenced/rich blocks. Edits shift unchanged plans in UTF-16 coordinates; selection, heading-separator context, and rendering settings determine reuse. Compare each requested line with actual native attributes before applying changes. Native font fallback and edit-notification ordering remain part of the rendering contract. Image plans recheck file metadata. See [render-plan validation](docs/render-plan-validation.md) for the measured costs and regression coverage.

Line layout reads the cached model. It must not parse the document again. Selection changes update reveal attributes without reparsing unchanged source. Native editors are retained by library/stream/day identity so switching a stream doesn't reset undo ownership. Shared height caches separate active, inactive, source-mode, width, configuration, and document contexts.

The timeline uses a single-column collection layout, with row geometry calculated from the same width as editor measurement. Both ordinary and context-based invalidation rebuild its cached frames; scrolling alone doesn't rebuild them. History paging triggers at the boundaries of retained rows, before entering spacer regions.

The current implementation retains TextKit 1. Existing caret and geometry APIs caused automatic fallback when tested with a TextKit 2 surface, so a genuine migration requires the layout and selection bridge to change together. Don't label the current renderer TextKit 2 or claim complete CommonMark compliance for its source-range scanner.

## Retrieval and state

⌘K opens commands, ⌘O switches streams, ⇧⌘F searches history, and ⌘F finds text in the active day. Search results show stream, date, and a clean highlighted excerpt while preserving the exact source range for opening the match. The switcher includes folder context and offers stream creation for unmatched names. Today and date navigation remain scoped to the selected stream. ⇧⌘Return toggles focus mode.

Remember each stream's active day, selection, scroll anchor, and collapsed days. Empty historical navigation must not create files. Keep history loading bounded and anchor by document identity plus viewport offset, not only total content height.

## Files and trust

Documents are identified by library root, stream UUID, and day key. All pending writes retain their original destination. A copied library with the same stream IDs is still a separate live namespace.

The versioned manifest stores root-relative paths, folder membership, ordering, pins, and archive state. Existing Markdown files and IDs survive migration. Folder and display-name changes are metadata changes. Search is derived from files, and deleting index data must never delete notes.

Clean buffers can reload external edits. Conflicting dirty buffers retain both versions for review. Normal quit flushes dirty data or stays open after a failed save. Recovery records are debounced by 150 ms, so forced termination before that write completes can lose the newest edits. Save indicators must represent actual canonical file persistence.

## Validation

Run `scripts/validate-local.sh all` for package tests and storage checks. Use `CurrentUIProbe` for isolated real-window rendering and editing checks with screenshots. Inspect both appearances and the minimum window width. The probe must never point at the user's actual library.

Core regression cases include fence deletion, incomplete syntax, Unicode and marked text, task editing, tables and images, repeated Return near the bottom, source-mode toggles, stream switching with queued saves, independent undo per day, old-note search, relocated libraries, recovery, and external conflicts. Performance claims require measured typing and scrolling traces on defined hardware; a passing screenshot or parser timing isn't enough.

The native shell passes 107 package tests plus storage checks, normal and long-document native exercises, and a narrow-window check. Sidebar keyboard focus and saved width restoration are covered; real-app review confirms native toolbar presentation and focus-mode visibility. Long-note viewport changes preserve editor identity, selection and undo. See [the validation record](docs/revamp-validation.md) for results and limitations. The macOS 14 fallback compiles but has not been runtime-tested on macOS 14.
