# Workspace restoration

Implemented September 28, 2026. The workspace restores the content being read separately from the note that owns the caret. Validation includes controller/window recreation within one process and a separate isolated-app quit/relaunch check.

## Contract

- The toolbar date follows the visible day. Its calendar opens at that date; Today is an explicit action when reading another day.
- Each stream saves its visible day, logical reading anchor, pixel fallback, editing day, UTF-16 selection, collapsed dates, and whether the visible editor had focus. Streams keep independent positions.
- Closing and reopening a window with the same controller must use the latest captured viewport, not its previous navigation request. A fresh controller reads the same state from `.current-session.json`.
- A saved blank day remains available even before the stream's creation date. A collapsed visible day stays collapsed. Restoring either does not create a blank note file.
- Restoring an offscreen caret must not scroll the reader back to it. Editor focus is restored only when explicitly saved and appropriate for the visible day and current native responder. Reading restoration must not steal focus from a sheet or text field.
- Forward midnight rollover updates Today while retaining the current editing day, loaded window, and reading position. Starting a new day's note requires explicit navigation.
- Markdown source mode and focus mode persist in workspace preferences so reopening does not silently change the presentation.

The reading anchor stores a source location, surrounding text, and displacement from its visual line. Restoration resolves nearby matching context and otherwise uses a clamped source location; the saved day offset remains a fallback when no text anchor is available. Caret selection is saved independently and clamped to the current source length. This is not persistence of native undo history or an unfinished IME composition across process termination.

## Causes addressed

The app-level controller can outlive its window. Previously, a new collection view replayed the old jump request, even when a more recent scroll position had been saved. `restoreCurrentViewPosition()` now issues a request from the latest state; the native view's initial snapshot also uses that state before SwiftUI's `onAppear` runs.

A pixel offset alone pointed at different text after width or font changes. `MarkdownReadingAnchor` now identifies source content. Restoration waits for the native editor's geometry to settle before resolving its final position. Temporary layout positions are prevented from replacing the saved state while restoration is pending.

Restoring a distant caret could remove a blank visible day from the loaded window, and reusing the direct-jump path expanded collapsed dates. The requested visible day is now pinned before publication, and saved collapse state is reapplied during restoration.

Session writes are debounced during ordinary scrolling. Final capture now runs before close/save/switch boundaries so the last viewport is available to the synchronous session flush. Native view dismantling captures position without triggering note-save publications during SwiftUI teardown.

Native typing reports its new selection before the editor's queued geometry publication. Capturing in that interval previously replaced a valid logical reading anchor with `nil`. The collection now keeps the last settled anchor for the same visible day while independently recording the latest selection, then refreshes the anchor when layout settles. A close capture is protected from later teardown publications overwriting its saved focus.

Reflow can temporarily detach and remount the same native editor. A successful `makeFirstResponder` return did not guarantee that it retained focus. Caret restoration now waits for measured geometry, checks the actual first responder, and retries when the mounted frame settles.

Older sessions can contain a pixel offset that extends beyond their named row. Those offsets retain their original meaning, without waiting for an editor that is now offscreen. New position captures filter collection prefetch items against the actual viewport before choosing the visible day. A new scroll request also cancels queued reflow from an older request; initial width preparation must not replay a top-of-timeline anchor after restoration completes.

Midnight previously called `jumpToToday()` when the old Today note was active, including while the reader was elsewhere. Rollover now updates the date without creating a new navigation request.

## Validation completed

The integrated run passed **142 Swift tests and `CurrentFeatureChecks`**. The new restoration suite covers immediate flush before the session debounce, cold-controller and same-controller restoration, distinct visible/caret days, old blank and collapsed dates, future notes, midnight, focus intent, legacy session decoding, and source/focus preferences. The rollover feature check now verifies that only an explicit Today action opens the new day.

The release native restoration probe passed **eight checks** using a 360-paragraph note of approximately 69,000 UTF-16 units. It closed and recreated the native window/host with the same controller, then created a fresh controller that loaded the session from disk. The latter changed editor width from 640 to 536 points and text size from 16 to 18 points. The same reading paragraph, caret selection, collapsed date, visible date, and reading focus were preserved. Reading-line offset error was below 0.1 point. Separate editing roundtrips restored the native first responder and visible caret, with reading-line error around 0.2 point.

The native probe runs in one process and retains the native editor-session cache. It does **not** establish process-relaunch behavior, restored undo history, or performance on substantially larger notes.

A separate isolated-app check used normal Command-Q, confirmed that the process exited, and reopened the app through LaunchServices with the same isolated configuration. The reopened screenshot showed Paragraph 180 at the viewport top. After another normal quit, the saved source anchor at UTF-16 location 34,295, surrounding context, selection `{1915, 13}`, collapsed September 27 date, and reading focus (`false`) were unchanged. Markdown SHA-256 hashes also matched. The recorded result is `/tmp/current-process-reopen.json`; this is separate evidence from the same-process probe above.

An actual bundled-app editing check also confirmed the note was focused on launch. Shift-Right changed its selection without clicking the editor. After normal quit and relaunch, another Shift-Right extended that same selection, with editing focus still saved and Markdown hashes unchanged (`/tmp/current-process-editing-reopen.json`).

The broader native regression probe passed **28 checks**, including the resize/focus path that had failed earlier, 1,017-line scrolling, and 130-day history. A native SwiftUI unit test mounts the timeline, scrolls to Paragraph 20, types in Paragraph 21, confirms geometry is still unsettled, and immediately flushes the workspace. The saved logical anchor stays unchanged while the on-disk selection advances with the edit. A second native test restores a legacy Today-plus-948-point offset into September 26, checking viewport position, the actual visible date, visible content, exact selection, and reading focus. It failed before the request-order fix and passes afterward.

Reproduction commands:

```sh
CURRENT_BUILD_PATH=/tmp/current-restoration-build scripts/validate-local.sh all
CURRENT_BUILD_CONFIGURATION=release CURRENT_BUILD_PATH=/tmp/current-restoration-build scripts/validate-local.sh probe --restoration-only --no-images --output /tmp/current-restoration-native
```

The restoration command creates a temporary app bundle and launches it through LaunchServices. This establishes a real key window for focus assertions; an unbundled command-line host cannot reliably activate on current macOS. The script checks the completed report and returns failure if the app crashes or a check fails.

## Remaining work

Extend end-to-end restoration coverage to external edits or missing saved context. The process-relaunch checks cover the isolated reading and editing fixtures above; they do not establish restoration of native undo or in-progress composition. Date-catalog paging, bidirectional distant jumps, Back history, timezone/clock reconciliation, unified height ownership, and byte/layout budgets remain in [the date-navigation plan](date-navigation-plan.md).
