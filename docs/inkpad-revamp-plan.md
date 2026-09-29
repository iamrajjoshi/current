# Inkpad revamp: product requirements and delivery plan

Status: design approved by the user and implemented on `raj--inkpad--stream-workspace`. Research date: September 27, 2026. The proposal below records the research and original gates; implementation differences and current validation are recorded at the top.

“Inkpad” refers to the app in this Current repository. No product rename, bundle-ID change, or storage-directory rename is proposed. Current was inspected at `a656cda40298dc9efc50f91a5a1137dfb527d550`; Flo State at `85a5c4b8d1d87d70418ef20272a9057fec119498`.

## Implementation record

The user approved daily streams first and implementation of the recommended sidebar/timeline design. The resulting app includes folders, stream lifecycle actions, optional tabs, date jumps, history search, a command palette, source mode, light/dark/system appearance, local image attachments, and rendered tables. No Flo State source or assets were copied and no new third-party dependencies were introduced.

The September 27 pass reviewed the user's screenshot and public [Bear interface](https://bear.app/) and [ChatGPT desktop examples](https://help.openai.com/en/articles/9703738-macos-app-release-notes#canvas). The September 28 [polish pass](polish-pass.md) supersedes the initial dimensions below: 640-point writing column, 16-point body text, 212-point sidebar, compact empty Today, grouped empty history, explicit tabs, and focus mode without the toolbar. Search excerpts, calendar indicators, table widths, and native edit-layout regressions are part of that pass. There are no filler cards in an empty note.

The implementation differs from the initial proposal in these areas:

- The app retains TextKit 1. A focused TextKit 2 spike showed that the existing layout/caret APIs triggered automatic fallback; a full bridge replacement is deferred. The revised render model and native input fixes are implemented on the existing TextKit surface.
- A one-pass block scanner with precise source ranges preserves the current editor's extensions and incomplete-input behavior. This isn't a claim of full CommonMark coverage. Source revision caching, old/new dirty-block expansion, and parse-free drawing/layout remove the identified repeated work.
- History search runs a cancellable background file scan, returning the newest 200 matching days and the first match in each day. It doesn't yet maintain a persistent full-text index. Tabs represent one view per stream.

Cross-day keyboard focus handoff remains deferred: arrow keys, undo, and Select All operate within the current daily document. Click another day or use date/search navigation to change documents. The interface does not support a selection spanning separate days.

Identity includes library root, stream UUID, and day key. Root-relative manifest migration, external-file observation, conflict review, and document-specific save queues are implemented. Dirty recovery is debounced by 150 ms plus write completion; a forced kill inside that interval can lose the latest edits. Orderly quit flushes pending data or refuses to terminate on failure.

The validation harness uses synthetic temporary libraries. It combines Swift Testing, the feature-check runner, a real-window native probe, source/layout comparisons, and manual menu/keyboard checks in a separately built app shell. See `revamp-validation.md` for the final evidence and remaining coverage limits. The proposed performance budgets later in this document remain acceptance targets until measured; passing a parser timing or UI smoke check does not establish frame-rate parity with another app.

## Recommendation

Make Inkpad a local writing workspace organized around streams. A collapsible sidebar holds folders and streams. Selecting a stream opens its continuous, today-first daily timeline. Give the writing surface readable rendered Markdown, predictable native editing, and stable scrolling. Add fast search, a command palette, date navigation, and optional tabs once document identity and saving are safe across streams.

The defining experience should be: open, write, switch context, find something from months ago, and return to exactly where you left off. Organization should never be a prerequisite for capture.

The largest change is the editor pipeline. More navigation around the current renderer would carry its faults into a more complicated app. Preserve the useful daily-file and native-input foundations, replace repeated parsing and competing geometry calculations, and prove the new engine before moving the entire interface onto it.

Confirmed product direction: daily streams remain the primary writing model; standalone notes come later. Standalone documents are not required to deliver this revamp.

## What the research establishes

The linked repository is now Flo State Native, using Swift, AppKit, and TextKit 2. Its React/CodeMirror frontend is a predecessor used as a behavioral reference. I built the native reference and inspected an offscreen rendering of its real shell and editor with synthetic notes. The screenshot shows a quiet folder sidebar, small tabs, readable proportional text, rendered tables, quote treatment, and code blocks. A static snapshot does not establish typing or scrolling performance. [Reference architecture](https://github.com/Altimor/flo-state/blob/85a5c4b8d1d87d70418ef20272a9057fec119498/README.md)

| Flo State mechanism | What Inkpad should adopt | Qualification |
| --- | --- | --- |
| Source text and selection feed a shared syntax tree and render plan | One authoritative document and one rendering model per document revision | Keep saved Markdown separate from display attributes |
| Cached syntax tree, block-level render-plan reuse, per-line attribute signatures | Reuse unchanged work; selection changes should not parse unchanged text | Flo State reparses the changed document; its parser is not fully incremental |
| Custom TextKit layout fragments | Derive decorations, caret, hit testing, and measurements from the same layout | TextKit 2 alone does not guarantee correct geometry |
| Native text input and minimal source replacements | Preserve IME, undo, selection, spelling, and standard editing | Do not rebuild the text view on each keystroke |
| Deferred editor creation for background tabs | Keep inactive contexts inexpensive | Share document state when multiple views address the same file |
| Fixtures, edit replay, geometry checks, real-window scroll tests | A reproducible quality harness and release gates | A passing parser test is not a passing interaction test |

Relevant source: [state/tree cache](https://github.com/Altimor/flo-state/blob/85a5c4b8d1d87d70418ef20272a9057fec119498/Sources/FloCore/Editor/State.swift#L652-L725), [render-plan cache](https://github.com/Altimor/flo-state/blob/85a5c4b8d1d87d70418ef20272a9057fec119498/Sources/FloKit/Editor/PlanCache.swift#L4-L158), [attribute application](https://github.com/Altimor/flo-state/blob/85a5c4b8d1d87d70418ef20272a9057fec119498/Sources/FloKit/Editor/EditorController.swift#L327-L395), [native layout](https://github.com/Altimor/flo-state/blob/85a5c4b8d1d87d70418ef20272a9057fec119498/Sources/FloKit/Editor/LayoutFragment.swift#L4-L138), [real-window regression tests](https://github.com/Altimor/flo-state/blob/85a5c4b8d1d87d70418ef20272a9057fec119498/Tests/FloStateNativeTests/EnterScrollTests.swift#L8-L76).

Two reference tradeoffs need different treatment here. Flo State forces full-document layout to stabilize estimated heights; doing that across an entire historical stream would be expensive. Its math, HTML, and Mermaid support also uses WebKit-backed rendering, despite native text input. Inkpad should bound layout by daily documents and treat asynchronous widgets as a separate feature with stable reserved dimensions. [Height correction](https://github.com/Altimor/flo-state/blob/85a5c4b8d1d87d70418ef20272a9057fec119498/Sources/FloKit/Editor/EditorController.swift#L860-L912), [math rendering](https://github.com/Altimor/flo-state/blob/85a5c4b8d1d87d70418ef20272a9057fec119498/Sources/FloKit/Editor/MathRenderer.swift#L5-L64).

Flo State states GPL-3.0-or-later licensing; Current uses MIT. The default plan is independent implementation of the architecture and interaction ideas, with appropriately licensed dependencies. Vendoring its editor, themes, or other source is a separate licensing decision before implementation, not an assumed shortcut. [Flo State license and dependency notices](https://github.com/Altimor/flo-state/blob/85a5c4b8d1d87d70418ef20272a9057fec119498/README.md#L141-L165)

## Current problems, with evidence

| Finding | Evidence | Implication |
| --- | --- | --- |
| Every line-fragment sizing callback constructs a full render model | `MarkdownEditorView.swift:57–74`; the model separately scans blocks and inline spans at `MarkdownEditorRenderModel.swift:58–65` | Layout work can repeatedly trigger document-wide parsing |
| Fence detection rescans preceding text for individual lines | `MarkdownBlockRendering.swift:227–234` | Some model construction grows poorly with document length |
| Timeline height comparison independently lays out old and new text | `TimelineCollectionView.swift:388–415`, `MarkdownTextLayoutMeasurer.swift:10–21` | Typing triggers work beyond the editor's own layout |
| Unclosed backtick fences and tilde fences don't protect inline content consistently | Isolated reproductions using the repository's parser/model sources | Formatting may be interpreted inside code; add regressions before replacing the parser |
| Dirty-region expansion can miss content after deleting an opening fence | Isolated `decorationRange` reproduction excludes the formerly fenced downstream span | Syntax changes must invalidate the whole affected block, including old boundaries |
| Document IDs, cache keys, and pending-save keys use dates alone | `CurrentModels.swift:25–28`, `DayCache.swift:3–15`, `TimelineController.swift:161–163` | Multi-stream support first needs stream-aware identity |
| Search inspects only loaded days | `TimelineController.swift:413–429` | A search box alone will not provide full-history search |
| Persisted stream metadata contains an absolute root URL | `CurrentModels.swift:3–8`, `StreamStore.swift:34–38` | Relocated libraries need root-relative path resolution |
| UI test coverage only checks window launch | `CurrentUITests.swift:10–14` | Add typing, selection, scroll, and navigation coverage |

The parser reproductions are confirmed at the model level, not observations of every corresponding live UI failure. One optimized, single-run probe took approximately 6 ms for 100 lines, 71 ms for 500 lines, and 258 ms for 1,000 lines (about 73,000 UTF-16 units). This is evidence of a hotspot, not a typing-latency benchmark or a direct comparison with Flo State.

Quit-time flushing is another risk to reproduce: `flushSaves()` exists, but the audited production call is associated with changing library roots, and the app entrypoint shows no quit flush. Do not claim observed data loss; test it explicitly.

## Information architecture

The hierarchy is Library → Folder → Stream → Day. A folder is an optional organizational group. A stream is a named, persistent sequence of daily notes. A day belongs to exactly one stream. A tab is an open view, not a content container.

```text
┌───────────────────────┬─────────────────────────────────────────────────┐
│ Inkpad                │ Work / TPRM                   Today   Jump to…   │
│ Search                ├─────────────────────────────────────────────────┤
│                       │                                                 │
│ Daily                 │          Today · Sunday, September 27           │
│                       │                                                 │
│ ▾ Work                │          Vendor review                          │
│   TPRM                │          Capture notes where they belong.       │
│   Payments            │                                                 │
│ ▾ Personal            │          ☐ Follow up on the evidence request    │
│   Journal             │          ☑ Review the intake checklist          │
│                       │                                                 │
│ Archive               │          Friday, September 25                   │
│ + New stream          │          Previous notes continue below…         │
└───────────────────────┴─────────────────────────────────────────────────┘
```

The default is one sidebar and one writing surface. Show the sidebar on a new library so streams are discoverable, then remember the user's choice. With one stream or in a narrow window, it can collapse to a compact stream picker. Focus mode hides navigation while leaving an obvious way to restore it.

Folders group streams; don't expose year/month/day filesystem paths as a mandatory navigation tree. Initially support one level of folders. Keep grouping in library metadata, so dragging a stream between folders does not move years of note files.

Date navigation belongs to the selected stream. A Today action and a date/history popover provide direct access to old days. A contextual date rail can be optional later. Don't show a permanent calendar, date column, folder tree, and tabs simultaneously by default.

| Layout | Strength | Cost | Recommendation |
| --- | --- | --- | --- |
| Streams/folders on left, timeline in center | Organization stays visible and can grow; preserves today's capture workflow | Uses horizontal space | Default |
| Streams in top tabs, dates on left | Fast movement among a small working set and its history | Tabs become an awkward full-library hierarchy as streams grow | Alternative shown for review |
| Streams sidebar plus optional open-view tabs | Good for repeatedly comparing two or three contexts | Duplicate navigation unless tabs have a clear purpose | Add within the revamp as opt-in session navigation |

Optional tabs open streams, retain per-view position, can be reordered/closed, and restore on relaunch. Closing a tab never archives or deletes a stream. One tab strip stays hidden until enabled or needed for a second open view. Multiple views of the same document share text, saves, and undo ownership; their scroll/selection state is separate.

## Requirements

### Reliable writing and rendering

| ID | Requirement | Acceptance |
| --- | --- | --- |
| E1 | Markdown remains canonical plain text | Rendering, hiding markers, theme changes, and resizing never change saved source |
| E2 | Live rendering for headings, emphasis, strike, inline/fenced code, quotes, links, lists/tasks, and rules | Reference fixtures render correctly, including incomplete syntax and nested combinations |
| E3 | Reveal syntax where the caret or selection needs it | Active logical line reveals inline syntax; active block reveals block-widget source; inactive content renders cleanly |
| E4 | Stable selection and text input | Drag selection freezes geometry-changing reveal until mouse-up; marked text/IME is preserved; Unicode and bidirectional text remain editable |
| E5 | Predictable commands | Return continues lists, empty items exit them, Tab/Shift-Tab indent appropriately, formatting shortcuts undo as coherent actions |
| E6 | Interactive tasks and links | Checkboxes update Markdown through undoable edits; link activation does not make link text impossible to edit |
| E7 | Escape hatch | A source mode exposes exact Markdown in the same document, keeping selection, undo, and saves coherent |
| E8 | Stable viewport | Enter, formatting, paste, day expansion, width changes, and widget completion don't unexpectedly move the reading anchor |
| E9 | Rich pasted content | Existing text/rich-text/HTML-to-Markdown paste behavior is preserved and tested; paste-as-plain-text remains available |
| E10 | Tables and local images | Render GFM tables and images; source editing is available in place; pasted/dropped images use relative attachments and undoable insertion |

Unsupported or incomplete constructs remain readable source. Rendering failures must never make text disappear. Existing syntax extensions, including underline behavior, need an explicit compatibility fixture before choosing a replacement parser.

Cross-day editing remains document-aware: undo and Select All apply to the active day, keyboard movement across day boundaries has an explicit focus handoff, and the UI must not imply an unsupported selection across independent documents. Cross-day range copying can be a separate later interaction.

### Streams, navigation, and retrieval

| ID | Requirement | Acceptance |
| --- | --- | --- |
| N1 | Create, rename, reorder, pin, archive, and restore streams | Same-date notes in two streams remain independent; archive is reversible |
| N2 | Create/rename folders and move streams between them | Folder removal ungroups streams without deleting their notes |
| N3 | Restore context | Stream switch restores date, caret, scroll anchor, and collapsed days; immediate switching after typing preserves the edit |
| N4 | Jump to today or a date | Loading an old day does not require scrolling through all intervening dates or create blank files |
| N5 | Search all saved history | Finds unloaded days; results show stream, date, and snippet and open the exact match |
| N6 | Local and global find | Native Find searches the active day; library search offers current-stream/all-stream scope; result navigation restores focus |
| N7 | Quick switcher and command palette | Stream switching, date jump, timestamp, focus mode, source mode, file reveal, and stream creation are keyboard-accessible |
| N8 | Optional open-view tabs | Tabs restore on relaunch, do not duplicate save ownership, and closing one never removes content |
| N9 | Preserve continuous review | Today-first ordering, collapsible history, bounded history loading, and no nested daily scrollbars remain |

Proposed shortcuts: Cmd+K for commands, Cmd+O for stream switching, Cmd+Shift+F for history search, Cmd+F for active-day find, Cmd+Shift+D for today, and Cmd+\\ for the sidebar. Audit existing shortcuts and standard macOS conventions before assigning conflicts. Menus must expose every shortcut action.

### Local ownership and trust

| ID | Requirement | Acceptance |
| --- | --- | --- |
| D1 | Local library with ordinary Markdown files | Capture, organization, and search work offline without an account |
| D2 | Safe autosave | Save state is accurate; write errors remain visible with retry; each queued save captures its immutable library/stream/file destination |
| D3 | External edit handling | Clean buffers reload safely; dirty conflicts retain both versions and offer review, keep-both, or explicit reload |
| D4 | Session and quit safety | Dirty buffers remain alive through view eviction; orderly quit flushes or reports failure; crash recovery is tested with a documented durability boundary |
| D5 | Portable storage | Resolve paths against the selected library root; copied libraries cannot write back to the original root |
| D6 | Non-destructive migration | Existing Markdown checksums and stream IDs remain unchanged; metadata migration is backed up, atomic, and repeatable |
| D7 | Rebuildable indexes | Removing search/cache data never removes notes; indexing observes external file creation, modification, moves, and deletion |
| D8 | Stable dates | Rollover and timezone changes cannot retarget edits or rename historical day keys implicitly |

Keep a small local recovery record for dirty content if the save/quit design needs it; define what survives forced termination before claiming crash safety. Save indicators represent actual durability, not just a queued timer.

### Visual and interaction direction

Use a neutral white writing canvas, subdued sidebar, system accent, and proportional system text by default. Keep a monospace preference and preserve explicit existing font settings. Code remains monospaced. The proposed default is 15-point body text with roughly 23-point line spacing, 22–24-point major headings, 17–18-point subheadings, and 12–13-point chrome. Confirm with actual TextKit rendering at common display scales.

| Token | Light | Dark |
| --- | --- | --- |
| Canvas | `#FFFFFF` | `#1E1E20` |
| Sidebar | `#F5F5F6` | `#262628` |
| Primary text | `#242426` | `#F1F1F3` |
| Secondary text | `#67676B` | `#B0B0B5` |
| Separator | `#E6E6E9` | `#3A3A3E` |
| Accent fallback | `#006DD8` | `#69AEFF` |

Use semantic system colors where appropriate; the values above specify the visual direction rather than overriding accessibility preferences. Keep a 680–760-point readable column, 220–260-point resizable sidebar, left-aligned prose, and useful whitespace. Day labels are subdued sentence case. A compact header identifies the current stream and offers Today/date navigation; save status stays close to the active day.

Animations should communicate a user action: about 120–180 ms for sidebar or disclosure transitions, with Reduce Motion honored. Never animate text reflow, caret corrections, or scroll compensation. Avoid decorative cards around each day, oversized toolbars, and a permanent status bar. Support light/dark/system appearance, visible keyboard focus, VoiceOver labels, adequate contrast, and usable layouts at the current minimum window size.

This deliberately changes the old design document's monospaced-only editing and no-top-bar rules. The quiet capture surface and transparent files remain; the new header and sidebar serve stream organization. Update DESIGN.md only after this direction is accepted.

## Technical direction

Prefer a native AppKit editor with a shared parse/render model and TextKit 2 as the target renderer. Keep SwiftUI for the surrounding shell where useful. Prove the editor in isolation before replacing the timeline's editor implementation. Apple describes TextKit 2's selection abstractions, layout fragments, and viewport layout, but those APIs still require careful integration with a growing timeline. [Apple's TextKit 2 introduction](https://developer.apple.com/videos/play/wwdc2021/10061/)

| Option | Assessment |
| --- | --- |
| Continue extending the current regex/highlighter/layout coupling | Small initial edits, but repeated parsing and overlapping syntax rules make full rendering parity harder; useful only for targeted baseline fixes |
| Shared parser/render plan plus native TextKit 2 | Recommended target; fits the native app and supports richer blocks while retaining platform input |
| Embedded CodeMirror editor | Credible contingency if native geometry/input gates fail; adds a web/native bridge and must prove focus, IME, paste, undo, and local-resource behavior |
| Direct FloCore/FloKit adoption | Closest source reuse, but couples the app to Flo State's assumptions and license; not the default plan |

CodeMirror already models viewport rendering and document decorations; evaluate it only if the native spike fails specific acceptance gates, not as a second full implementation. [CodeMirror system guide](https://codemirror.net/docs/guide/)

Start parser evaluation with `swift-markdown`/cmark-gfm because it provides an established GFM parser. It is not a drop-in live editor or a guarantee of incremental parsing. Verify exact delimiter/source ranges, incomplete syntax, compatibility extensions, and UTF-8-to-UTF-16 mapping before selection. Pin a tested version and preserve dependency notices. [Swift Markdown](https://github.com/swiftlang/swift-markdown)

The intended pipeline is:

```text
Native input / editing command
    → source edit + revision + selection
    → cached syntax tree / block structure
    → render plan for affected old and new blocks
    → changed attributes and widgets
    → TextKit layout, caret, hit testing, measured height
    → anchored timeline update

Source revision → document store → autosave / recovery / search index
```

Key constraints:

1. A stable document session owns text, dirty state, undo, pending writes, and revision. View lifecycle must not own durability.
2. Cache parsing by source revision, not selection. One parse per changed revision is an acceptable starting point if measured budgets pass; do not build a speculative incremental parser first.
3. Expand changed regions using both old and new syntax structure. Removing a fence or altering list nesting may affect much more than adjacent paragraphs. Fall back to a full plan when correctness cannot be established.
4. Reuse unchanged line/block attributes. No parsing in drawing or line-sizing callbacks. Styling updates must not enter the user's undo history.
5. Caret, selection, rules, widgets, and height use the same layout output. Remove independent old/new full-document measurement from the ordinary typing path.
6. Keep separate daily documents and virtualize the outer timeline. Anchor scrolling by document ID, text position, and relative vertical offset, rather than total content height alone.
7. Inactive days reuse the same render-plan semantics. Bound caches by cost; pin dirty sessions, not all their views. For unusually large days, the spike must prove how native viewport layout integrates with outer scrolling.
8. Expensive parse/index/widget work can use immutable snapshots off the main thread. Cache parsing by source revision; apply presentation results only if their render generation still matches source, selection, source/live mode, width, and theme inputs. Text input and IME must never wait on an async renderer. Test caret movement and resize while results are pending.
9. Reserve image/widget dimensions, cancel obsolete rendering work, and preserve the visible anchor when final dimensions arrive. A failed renderer leaves editable source.

### Data changes and migration

Introduce `DocumentID(streamID, dayKey)` within a library-scoped session namespace before enabling another live stream. Copied libraries preserve stream UUIDs, so an original and its copy must never share live sessions just because those IDs match. Replace date-only keys in caches, save queues, collection items, collapse state, navigation, and search results. Keep view state separate from document identity. Capture each pending save's original destination; verify root switching while a write is outstanding and both libraries contain identical stream/day IDs.

Add a versioned library manifest for stable stream IDs, display names, relative paths, folder membership, ordering, pins, and archived state. Session metadata stores current stream, sidebar state, optional tabs, and per-view positions. Search data is derived and rebuildable.

Adopt the existing `streams/daily/YYYY/MM/YYYY-MM-DD.md` structure in place. Preserve stream UUID and source bytes, back up metadata, resolve old absolute URLs against the selected library, and commit new metadata atomically. A display-name or folder change does not need a physical rename. Recover from interrupted migration and handle damaged metadata by discovering existing files rather than silently creating a new empty library.

## Delivery sequence and gates

| Milestone | Work | Exit gate |
| --- | --- | --- |
| 0. Baseline and failure corpus | Add isolated test-library launch support, record current bugs, fixtures, UI traces, and save/quit behavior | Each reported rendering defect has a reproducible case; baseline data survives tests |
| 1. Native editor spike | Shared parser/source map/render plan, TextKit 2 surface, core blocks, selection/IME, height/scroll bridge | Same source renders correctly; real-window caret/scroll tests and latency budgets pass on small and large days |
| 2. Document ownership and editor integration | Establish library-scoped document sessions, stream-aware IDs, and immutable save targets; connect the bounded timeline to the new editor; reuse measured geometry and preserve commands/paste/undo | Existing capture behaviors and failure corpus pass; no editor recreation while typing; sessions survive view recycling |
| 3. Library foundation | Manifest migration, stream lifecycle, safe switching, file watching/index groundwork | Two same-date streams cannot leak text/state; migration checksums, quit, conflict, and relocation tests pass |
| 4. Navigation and visual redesign | Sidebar/folders/streams, restored positions, Today/date jump, theme/typography, focus mode | Core flows work by mouse, keyboard, and VoiceOver at supported window sizes |
| 5. Retrieval and open views | Full-history search, snippets, quick switcher, commands, optional tabs/session restore | Old unloaded notes are searchable; tab switching retains focus/undo/saves; large libraries stay responsive |
| 6. Rich content and release hardening | Local images, rendered tables with source editing, long-session profiling, accessibility and failure QA | Widget loads preserve anchors; performance and durability gates pass; manual release is reviewable |

Document-session and library-model work can proceed in parallel with the isolated editor spike after the requirements are accepted. Timeline integration depends on both the editor gate and the session/save foundation; the shell depends on the library model. Don't split ownership of the same save or editor lifecycle across concurrent implementation efforts.

If the native spike fails the agreed geometry or input tests, stop there and compare a small CodeMirror proof against the exact same fixture set. Choose based on evidence before building the rest of the interface around either implementation.

## Definition of done

Performance numbers below are proposed acceptance budgets, not measured current performance or claims about Flo State. Calibrate once using a named Apple Silicon baseline Mac, release builds, macOS 14 and the current supported OS, fixed window/font settings, and identical local fixtures. Record distributions and traces; do not quietly relax failing targets.

| Check | Proposed budget / expected result |
| --- | --- |
| Ordinary typing in a 10–100 KB active day | Key event to presented update p95 ≤ 16.7 ms; separately track parse, apply, layout, and display time |
| Large 1 MB day stress test | Editable throughout; p95 ≤ 50 ms; no stale content overwrite or disappearing text |
| Warm stream switch | Visible saved context ≤ 100 ms; no empty flash or wrong caret |
| First editable launch | ≤ 1 second after process launch with an existing local library on the baseline machine |
| Warm search over a fixed 10,000-day / 100 MB corpus | First useful results ≤ 200 ms after query dispatch, with cold indexing remaining cancellable and nonblocking |
| Scrolling | Target display cadence under the fixed fixture; no unexplained visible-anchor drift greater than 1 point after an update settles |
| Cache behavior | Memory settles after repeatedly visiting many streams/days; no monotonically growing editor/view cache |
| Native behavior | IME, emoji, combining marks, RTL, drag selection, undo/redo, spellcheck, find, and keyboard commands pass real-window tests |
| Persistence | Same-date streams isolated; failed writes/conflicts recoverable; dirty state survives view eviction; orderly quit/reopen preserves edits |
| Migration | Original note hashes unchanged; repeated migration is idempotent; copied library writes only inside its selected root |

The fixture corpus must include unfinished/backtick/tilde fences; adding/removing a fence far above the viewport; nested and task lists; horizontal rules at EOF; long links; heading changes; tables; pasted meeting notes; large single paragraphs; emoji/combining characters; mixed-direction text; and images completing above the caret.

Verify full rendering against incremental rendering after deterministic edit sequences and randomized edits. Assert both source/selection results and actual geometry. Run real-window tests for Return near the bottom edge, changing a block's height above the viewport, selecting across hidden markers, switching immediately after typing, midnight rollover, and opening old search results. Offscreen screenshots supplement these tests.

A release must pass the relevant unit, integration, UI, geometry, and performance gates. Existing CI remains the validation path. App releases remain manual through the repository's Release workflow.

## Deliberately outside the first delivery

Cloud accounts/sync, collaboration, AI editing, mobile apps, arbitrary plugin systems, and standalone document management are outside this delivery. Wiki-links/backlinks, saved searches, math/Mermaid, typewriter scrolling, and an optional outline/date rail can follow once the core gates are stable. Raw HTML rendering should be a separately specified feature; existing HTML-to-Markdown paste remains supported.

The remaining review decisions are the sidebar as default, optional tabs as views, proportional default typography with a monospace preference, and independent native editor implementation. The exact parser and final TextKit 2 integration remain engineering decisions gated by the spike.

## Research validation record

Flo State was built successfully with `swift build --product FloStateNative -j 4`. Its `--shell-snapshot` mode rendered a synthetic notebook at 1200 × 800 points using an isolated data directory. This verified the inspected layout and selected rendered blocks, not live interaction performance or complete feature parity.

The Current parser probe compiled three unchanged repository source files with `swiftc -O`: `MarkdownBlockRendering.swift`, `MarkdownInlineRendering.swift`, and `MarkdownEditorRenderModel.swift`. Toolchain: Apple Swift 6.3.3, target arm64-apple-macosx26.0. It produced these diagnostic results:

| Probe (escaped newlines shown literally) | Result |
| --- | --- |
| `"```swift\n**not emphasis**\n"` | Zero protected ranges, one inline formatting span inside code |
| `"~~~swift\n# not heading\n**not emphasis**\n~~~\n"` | Zero protected ranges, one heading and one inline span inside code |
| Remove the opening backticks from a fenced block containing three code lines before `**not emphasis**` | Invalidated range `{0,16}` excludes the downstream range `{36,16}` |

The timings above used 100/250/500/1000 repetitions of `Regular line with **bold** and *italic* and [link](https://example.com).`, joined with newlines. They were a single diagnostic run without warmup or UI rendering. Repeat them under the benchmark protocol before making release-performance claims.

`swift test --package-path CurrentPackage --scratch-path /tmp/current-render-audit-20260927/build` compiled production sources but failed compiling tests with `no such module 'Testing'`. The full test suite was not validated in this environment. The delivery baseline must repair or select the supported test toolchain before implementation gates can rely on it.

`swift run --package-path CurrentPackage --scratch-path /tmp/current-render-audit-20260927/build CurrentFeatureChecks` passed. The review-only navigation mockup passed JavaScript syntax and markup checks; browser checks verified stream switching, focus mode, tabs, and date switching, with visual inspection at desktop, 736-pixel, and 320-pixel widths. This mockup validates the proposed navigation, not the native renderer.
