# Workspace revamp validation

Validated locally on September 27–28, 2026, using Apple Silicon macOS 26, Swift 6.3.3, and Command Line Tools. All fixtures use temporary libraries. No release was created.

## September 28 native macOS shell pass

The workspace now uses a native `NavigationSplitView`, sidebar-styled `List`, and unified window toolbar with the title hidden. Standard controls receive the operating system's styling; macOS 26 toolbar spacers and glass focus-exit styling have macOS 14 fallbacks. The first day begins 8 points below the native content boundary. Optional tabs remain explicit, and automatic macOS window tabbing is disabled to avoid two competing tab systems.

The final package run passes 107 tests plus `CurrentFeatureChecks`. Optimized native runs pass 29 normal-workspace checks and 29 combined long-note/history checks. Five static checks pass at 820 × 640 whole-window size. The combined fixture starts at 1,012 lines and 45,862 UTF-16 units, exercises nine large scroll positions, and finishes at 1,017 lines after scripted edits. Its 130-day library completes 21 older/newer paging transitions while retaining at most 60 days, with no blank viewport. Logs contain no AttributeGraph, layout-constraint, or collection-width warnings.

Repeated sidebar arrow selection now retains list focus, saves the previous note and preserves undo without adding tabs. The saved sidebar content width survives restoring preferences into a fresh workspace. Native splitter geometry includes system insets, so assertions compare the same coordinate system. Height-only viewport changes with the sidebar hidden preserve a caret near the long note's end, subsequent input and undo.

Real app review on macOS 26 covered dark and light appearance, compact window layout, sidebar selection and folder disclosure, Today, the stream-creation sheet, explicit tabs, and focus entry/exit with the sidebar already hidden. The actual `WindowGroup` hides the toolbar and window controls in focus mode. The bare `NSHostingView` probe does not implement scene-level toolbar visibility, so it tests document continuity separately. Calendar opening was confirmed in the actual app's visible native popover window. Native calendar tests also cover written and blank dates, focus after selection, external writing-marker changes, and no file creation from viewing an empty date.

Native toolbar accessibility press can return `false` while successfully firing its action. The probe therefore invokes the action once and checks resulting state and popover visibility; it does not retry based on that return value. Main-window accessibility capture omits the separate native popover window. Calendar opening is idempotent to avoid closing it on repeated activation.

The optimized combined run measured 7.52 ms median, 8.72 ms at the 95th percentile, and 14.28 ms maximum for 38 native insertions including forced TextKit layout; paste took 11.71 ms. These timings exclude subsequent view display and are not input-to-screen latency or frame-rate measurements. Ending process footprint was 267.9 MB (255.5 MiB), and the 59.21-second run includes intentional settling and captures. The probe now drains an autorelease pool around synchronous initial window mounting; previously retained startup temporaries inflated its memory result. This is a measurement-harness correction, not a production renderer optimization. Real-app before/after comparison showed a similar transient startup peak of roughly 950–963 MiB with the same long fixture, predating this shell change.

The release app and availability guards compile with a macOS 14 deployment target. Runtime and visual checks were performed on macOS 26 only. The earlier pass below records renderer fixes and prior measurements separately.

## September 28 writing-surface polish pass

The composition now uses a centered 640-point writing column, 16-point body text, compact empty Today, quieter dates, a 212-point sidebar, explicit tabs, and a focus mode that hides surrounding navigation. Search excerpts remove Markdown syntax and highlight the matched text. Calendar indicators track saved and unsaved content, including external changes while the popover remains open. Short tables size to their content. Existing-stream links resolve and complete without changing the source model.

The mounted workspace passes 26 normal native checks. These include opening both written and blank calendar dates with the correct first responder, no file creation from merely viewing a blank date, live calendar indicators after external file creation/removal, collapsed excerpts, empty-history disclosure, folder-aware stream creation through Return, explicit tabs, focus mode, search source selection, native completion replacement/cancellation/undo, and resolved link activation. Direct completion-method checks do not by themselves verify the visible system popup's keyboard routing.

Three rendering failures were reproduced against a freshly created editor: stale glyph properties after native paste/edit, an incorrect paragraph boundary around hidden heading prefixes, and missing emoji fallback glyphs after font styling. Syntax decoration now runs within TextKit's sanctioned post-edit callback; custom glyph invalidation is scoped to the affected range, and heading prefixes preserve their native paragraph boundary. Native font coverage is repaired after styling so emoji fallback glyphs remain present. Measurements wait for the native edit transaction to finish and are refreshed after composition styling; the initial stale-height reproduction used a windowless fixture, and the final regression uses a mounted editor. Regression checks compare source, selection, visible glyphs, line fragments, and reported editor height through paste, Unicode edits, fence changes, undo/redo, resize, appearance changes, and source mode.

The calendar regression also caught a retained SwiftUI popover whose disappearance callback never ran. Date selection now queues the jump directly after closing the popover, with library/stream/request guards. A switcher regression caught reused row identity displaying the wrong creation label; rows now have stable semantic identities.

Actual app keyboard testing found failures that direct completion-method tests missed. Native completion could dismiss without its final callback, leaving suggestions blocked. Requests now re-read the current query after queued input. Acceptance runs after AppKit finishes its tracking cleanup, with source/selection/document guards, so the framework cannot overwrite the accepted link. Typing `[[Da`, selecting with Down, accepting with Return, cancelling with Escape, typing again, and Command-Z/Shift-Command-Z were exercised in the app.

The same test exposed native undo actions reaching SwiftUI's window instead of the note's retained undo manager. The editor now owns `undo:`/`redo:` responder actions and validates their menu state, including marked-text protection. Native keyboard undo and redo restore the exact pre-completion source. The New Stream command also replaces SwiftUI's default New Window command group to give Command-N one meaning. In the final optimized app, Command-N opened the creation sheet in the existing window; two filtered suggestions could be selected with arrow keys; undo/redo and subsequent normal typing worked; Save Notes plus a clean quit left exactly `[[Data]]` on disk in the isolated fixture.

The complete package suite passes 105 tests plus `CurrentFeatureChecks`. Optimized native validation passes 26 normal-workspace checks and 25 combined stress checks. A 1,012-line, 45,862-UTF16-unit note remains correct across nine large scroll positions; a separate 130-day library completes nine older, six newer, then six older window transitions while retaining at most 60 timeline days. Dark and light 1200 × 820 layouts and the narrow 820 × 640 layout each pass four static checks and visual review. The final logs have no AttributeGraph, state-publication, collection-width, or exception warnings.

In the optimized build, 38 native character insertions into the long note measured 7.54 ms median, 8.38 ms at the 95th percentile, and 12.21 ms maximum, including forced TextKit layout. Paste measured 10.21 ms. These synchronous measurements exclude subsequent run-loop view layout/display; they are not input-to-screen latency or a frame-rate claim. The sampled process footprint was 709 MiB immediately after the uninterrupted input burst, at most 373 MiB at sampled scroll positions, and 358 MiB at completion. The run took 47.42 seconds including intentional settling and screenshots. Fixture/build mode and autorelease timing affect memory measurements.

A debug comparison before scoped invalidation measured roughly 67 ms median per input/layout, versus about 11 ms after the fix. Treat that comparison as diagnostic evidence, not a hardware-independent performance guarantee.

The earlier baseline results below are retained to distinguish the original revamp from this later pass.

## Automated checks

```bash
scripts/validate-local.sh all
scripts/validate-local.sh probe --exercise --stress --history-days 130 --output /tmp/current-ui-check
scripts/validate-local.sh probe --dark --width 820 --height 640 --output /tmp/current-ui-narrow
```

The original package baseline passed 75 tests, followed by `CurrentFeatureChecks`. Coverage includes source-preserving Markdown rendering, old/new fence invalidation, Unicode, composition suspension, selection without reparsing, trailing-newline caret geometry, task alignment, tables, local images, storage identity, migration, recovery, external changes, conflicts, search, and native timeline layout invalidation.

The history stress fixture contains 1,827 notes spanning five years. It visits every day across more than 100 window changes in each direction, verifies source and ordering, and retains at most 62 documents for a 60-day window plus the current/caret days. Separate sparse-history coverage skips empty date ranges spanning roughly eleven years. These are controller/storage tests, not scroll frame-rate measurements.

## Native interaction checks

`CurrentUIProbe` mounts the actual SwiftUI workspace, collection view, and AppKit editors in a real window. It writes screenshots and `geometry.json` with the exact checks, editor bounds, process footprint, and scroll samples. The fixture covers headings, lists, tasks, quotes, fences, tables, and a local image.

The interaction exercise checks typing without replacing the mounted editor, exact undo/redo source, marked-text composition and commit, repeated Return at the end with a visible caret, disk persistence, window resize, source mode, appearance, repeated stream switching, optional tabs, focus mode, date jumps, and selecting a full-history search match. It also checks that resizing and changing presentation don't reveal hidden table/image source markers.

A separately compiled `Current.app` shell was exercised through native keyboard input: command palette, stream picker, search, stream switching, Save Notes (⌘S), and normal quit after an edit. Rereading the fixture file confirmed the quit flush. This checks the real app menus and lifecycle in addition to the probe.

A separate native history run uses 130 daily files with a 60-day retention window. It completed 9 older, 6 newer, and 6 older window transitions, reached spacer regions over 12,000 points long, and checked that every viewport contained real note content with the correct source. The run retained at most 60 timeline documents.

The original revamp combined run passed 20 native checks: a 1,008-line mixed note across nine large scroll positions, the 130-day history sequence, window resizing with editor identity/caret/keyboard focus intact, source/theme changes, and exact model and file bytes after cross-stream undo/redo. The log contains no collection layout, AttributeGraph, or state-publication warnings. Peak sampled process footprint was 385.7 MiB; ending footprint was 381.5 MiB. Its 32.18-second validation duration includes intentional settling and screenshots, not just editing or scrolling work.

Dark appearance at 1200 × 820 and light appearance at the minimum 820 × 640 each passed four additional mounting/rendering checks and visual review. Table columns, sidebar controls, and writing content fit those windows. The original pass also added a regression for an unchanged short note whose minimum editor height changes at midnight; the complete package suite covers that final adjustment.

## Problems reproduced and fixed

- Full-source bridging from native text-storage length and per-glyph attribute access caused extreme memory growth in a 1,000-line note. Cached source snapshots, direct native attribute getters/setters, and effective-range reuse remove those repeated allocations.
- Explicit display invalidation inside a text-storage editing transaction could force glyph generation and crash on typing. Attribute-edit notifications now drive invalidation.
- A generic text-color setter overwrote hidden syntax colors after resize. The highlighter now owns per-range styling.
- Synchronous collection updates during SwiftUI reconciliation caused AttributeGraph cycles. Snapshot application is coalesced after that update.
- Flow layout cached incompatible widths and section insets during resizing. A single-column layout calculates both together; tests cover ordinary and context-based invalidation, changed heights, resizing, insertion/removal, and visible-rectangle filtering.
- Keeping an absolute offset while a tall note contracted on window resize could land in another day. Reflow now preserves position within the original row, then restores a visible editing caret after native layout settles.
- Hidden collection reuse could replace a document's native editor and undo session. Safe session transfer clears the old host and guards delayed callbacks by editor ownership; detached session retention is bounded to eight editors or 250,000 source units, with the active editor protected.
- Undo returning to a row model's older source could skip the canonical update. All native buffer changes now reach the document, with undo and redo checked against saved file bytes.
- Bottom-spacer paging waited until the end of unloaded history. Paging now measures from the oldest retained row.
- Jumping back to Today could reuse a previously requested history boundary and suppress further loading. Boundary request guards now reset with changed windows or explicit jumps.
- Deferred callbacks could act on a previously selected stream or stale search results. Document/library guards and search completion checks restrict those actions to their intended context.

## Coverage limits

The editor still uses TextKit 1 and a source-range Markdown scanner; this work doesn't establish complete CommonMark conformance. Search scans files in the background and returns up to 200 matching days, rather than using a persistent full-text index. Rich rendering covers local images and tables; remote embeds, math, and diagrams remain outside this change.

The native probe's elapsed time includes deliberate run-loop settling and screenshots. It isn't a typing latency or frame-rate benchmark, and its process footprint depends on fixtures and build mode. Marked-text API checks don't certify every installed IME. Cross-day arrow-key focus handoff remains deferred; each day owns its selection and undo. VoiceOver, a broad macOS-version matrix, and prolonged real-world soak tests remain unverified.

Full Xcode app/UI test execution is unavailable on this machine because the installed Xcode license hasn't been accepted. The package tests, native probe, and separately compiled app shell run with Command Line Tools. No agreement was accepted as part of this work.

Normal quit flushes dirty notes; recovery journals are debounced by 150 ms plus write completion. Forced termination inside that interval can lose the latest edits. Undo sessions are bounded in memory and aren't persistent across app launches.
