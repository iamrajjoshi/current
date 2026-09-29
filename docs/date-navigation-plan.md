# Date navigation and typography

Updated September 28, 2026. The visible-date toolbar and workspace restoration described below are implemented. The remaining date, paging, and typography work is a proposal. The accompanying interactive study demonstrates design choices; it is not a native performance test.

## Implemented in this pass

The toolbar date follows the visible day and opens the calendar at that date. Its label uses the current locale and includes the year outside the current year. Today appears as a separate action when reading another day. Search, the stream breadcrumb, and optional tabs remain available.

Workspace state now saves a source reading anchor separately from the caret selection. Window reopen and fresh-controller restoration use that anchor after native layout settles; blank and collapsed visible days stay in place. Midnight updates Today without issuing a jump or moving the existing editing day. Source and focus modes persist. See [Workspace restoration](workspace-restoration.md) for the contract, root causes, and validation limits.

The integrated Swift suite passed 142 tests and `CurrentFeatureChecks`. The bundled native restoration probe passed eight checks covering reading and editing focus, width/font changes, and fresh controllers. Separate isolated-app checks confirmed normal process quit/relaunch with the same reading position or editing selection and unchanged Markdown hashes. The broader native regression probe passed 28 checks, including long-note scrolling and 130-day history. Two native unit tests cover immediate close during unsettled typing layout and legacy offsets that extend into an older date.

## Recommendation

Keep the continuous, newest-first stream. Scroll through days containing writing, keep Today available as a compact entry, and use one persistent date control to reach any other day. Put that control in the existing toolbar so long notes retain date context without adding another permanent header. Keep the folder/stream breadcrumb at the leading edge. Ordinary sidebar selection replaces the current stream; tabs remain an explicit option.

The implemented date control follows the day being read, not the last editor focused. Opening it shows that month, writing indicators, and direct date entry. Today is available when away from Today. A Back action after deliberate jumps, stable space for contextual actions, quieter day headings with separate disclosure, and local day actions on hover or keyboard focus remain proposed.

An alternative is a sticky day label at the top of the writing viewport. It makes context more prominent but costs another row and repeats the toolbar calendar affordance. Prefer the toolbar date for the compact workspace requested here.

## Baseline findings and current status

| Finding | Source | Required behavior |
| --- | --- | --- |
| A direct old-date jump clears the spacers; both newer-page paths require a positive top spacer. | `TimelineController.jumpToDate`, `loadNewerWindow`; `TimelineCollectionView` newer paging | Load either direction after any jump. Date availability must not depend on pixel heights. |
| The calendar previously opened at `activeDate` despite a separate saved `scrollDayKey`. | `TimelineCollectionView` viewport recording; `ContentView` calendar button | Implemented: the toolbar and calendar use the visible date. |
| Midnight previously jumped to Today when the old Today editor remained active. | `TimelineController.handleDayRollover` | Implemented: forward rollover preserves viewport and editing day. Wake, backward clock, and timezone reconciliation remain proposed. |
| Sparse streams materialize empty dates after their creation date and group them afterward. Earlier imported history skips gaps. | `TimelineController` date paging; `TimelineHistoryPresentation` | Identical written history should browse identically regardless of stream creation time. |
| Existing day labels force English, omit years, and use separately captured calendars. | `CurrentModels.shortTitle`, `monthDayTitle`; `WorkspaceCalendar` | Toolbar localization and historical years are implemented. Day-label consistency and a shared storage-date policy remain proposed. |
| Body font size and line height are independent values; several UI sizes are set locally. | `CurrentConfiguration`; `CurrentTheme`; calendar and day views | Central semantic roles and line metrics that follow the chosen writing size. |
| Restoration previously used only a day and pixel offset. Omitted heights still have more than one accounting owner. | `StreamLibrary`; `TimelineCollectionView`; `TimelineHistoryPresentation` | Implemented: source-context restoration with pixel fallback. Unified geometry estimates and restoration through arbitrary external edits remain outstanding. |
| The production default retains 180 dates; the prior stress fixture used 60. Retained dates escape the clean-document cache limit, and uncached heights lay out full notes. | `CurrentConfiguration.defaultHistoryWindowDays`; `DayCache`; `MarkdownTextLayoutMeasurer` | Bound retained source bytes and layout work as well as document count. |

These are implementation findings, not a claim that every issue has been reproduced through the app UI. Existing long-history tests start from Today and do not establish correct newer paging after a distant direct jump.

## Date behavior

This is the target behavior. The toolbar's visible-date state and forward-midnight preservation are implemented; the wider paging, history, and clock policies below remain proposed.

- Use distinct `todayKey`, `visibleDayKey`, and `editingDayKey`. Publish visible-date changes only when another day crosses the reading edge, not on every scroll pixel. A note continues to own its caret and composition while scrolling.
- Default history contains written days, Today, and an explicitly opened blank day. Do not create files by browsing. Do not show a ladder of empty dates or a collapsed-gap row for every absence; the date labels already communicate gaps. The calendar remains complete.
- Display Today or Yesterday with a localized short date. Include the year outside the current year. Expose the complete weekday, date, and year to accessibility. Calendar Today and selection must differ by shape or outline as well as color.
- Calendar entry accepts exact dates initially. Add natural-language dates only when parsing is predictable and shows the resolved date before opening. Previous/next written-day commands must be named distinctly from previous/next calendar day.
- Save navigation history for calendar, search, links, and Today jumps. Wheel scrolling does not create Back entries. Back restores the stream and logical reading position, without unnecessarily moving keyboard focus.
- Support future-dated writing deliberately: an explicit calendar jump can open a future blank day; saved future entries remain in the ordered date catalog. Opening a stream defaults to the restored position or Today, and newer paging can reach existing future entries. Never materialize every future empty day.
- Midnight, wake, timezone, and manual clock changes update Today and calendar indicators. Existing writing remains assigned to its original day until the user explicitly starts the new day. Do not automatically rename files.

## Typography and controls

Consistency means a stable hierarchy, not identical sizes everywhere. Apple distinguishes system fonts for interface text from document fonts for user content. Use system APIs for native UI text and a user-selectable writing family for prose and headings. Code keeps a monospaced family.

| Role | Starting point | Scaling rule |
| --- | --- | --- |
| Native navigation and controls | Platform default, approximately 13 pt | Follow native control/text styles; do not force the writing font onto controls. |
| Day heading | 13 pt, medium | Fixed UI role; localizable and accessible. |
| Excerpts and secondary metadata | 12 pt, regular | One secondary role with adequate contrast. |
| Prose | 16 pt, 1.6 line-height ratio | Font size drives line spacing; respect actual font metrics. |
| Heading 1 / 2 / 3 | 26 / 21 / 18 pt at the default size | Derived from the body scale, using its family; coordinated before/after spacing. |
| Code | 15 pt at the default size | Monospaced, proportional to body scale, with safe glyph metrics. |

Use one resolved typography value set for SwiftUI labels, AppKit attributed text, and layout measurements. Larger fonts, fallback glyphs, CJK, emoji, and code must not be clipped by fixed line boxes. Cache keys include the resolved typography revision.

Start with a centered column near 640 points at the default font. Offer Standard and Wide reading measures, targeting approximately 64 and 72 characters, rather than claiming an exact proportional-font character count. Scale width with writing size within the available viewport. Let tables expand deliberately when their contents require it.

Add a native Settings writing panel for font, text size, reading width, and line spacing. Keep detailed paragraph spacing and configuration-file editing secondary. Text zoom should update the same typography model. Do not scatter formatting controls above every day. Keep Search available in the toolbar, consolidate date actions into its date control, and put New Stream in the existing library/breadcrumb menu with its keyboard shortcut.

Use platform controls and semantic materials where appropriate, behind existing compatibility boundaries for older macOS versions. Avoid custom gradients, duplicate pill containers, promotional placeholder copy, and animation of editor geometry. Honor Reduce Motion; short state transitions must not delay typing or alter selection.

## Architecture

Keep AppKit text editing, the existing line render-plan cache, and the collection view. The next work is the date/paging contract, not another editor rewrite.

1. **Civil date identity.** Introduce a validated Gregorian `DayKey` for persisted identities, separate from localized presentation and the clock's timezone. Preserve existing paths; audit compatibility before changing how older non-Gregorian configurations resolve keys. A shared clock context supplies Today and change events.
2. **Date catalog and slices.** Build on the existing sorted date index. Binary-search it for written days, calendar presence, and a target-centered `TimelineSlice` with independent newer/older cursors. Blank requested dates are transient exceptions. Files remain canonical; an index can be rebuilt. A database is unnecessary at this scale.
3. **Logical viewport anchor.** Implemented for workspace restoration: save the day, source location and nearby text, visual-line offset, and a day-pixel fallback. Caret selection and focus intent are separate. Further work must verify all reflow/prepend paths and define offset handling through arbitrary local or external edits. Composition remains owned by the live native editor; an in-progress composition is not serialized as a restartable session.
4. **Single geometry owner.** Timeline layout owns measured and estimated heights, keyed by day revision, width, typography revision, and source/rendered mode. Geometry never decides whether dates exist. Refine estimates near the viewport while preserving the logical anchor; cancel obsolete generations.

Enumerate and read files off the main thread, update catalog entries from file events, and reject stale results when stream or layout generation changes. Use a bounded prefetch region. Budget mounted editors, retained clean source bytes, and synchronous layout work separately. Protect unsaved edits independently of whether their views are mounted; never evict unsaved text to satisfy a cache limit.

The scrollbar represents the loaded reading window, not an exact linear map of every day in ten years. Use the calendar and typed date jump for distance. Do not imply that equally spaced pixels equal equally spaced dates.

A very large single-day note remains a separate limitation: day virtualization does not make full-note parsing or measuring cheap. Profile 10k- and 100k-line notes independently. If measurements require it, add block/viewport-aware measurement while retaining one coherent editing session, selection, IME, accessibility, and undo. Do not make one independent editor per visual line.

## Build order and acceptance

The toolbar and bounded workspace-restoration pass is implemented; it does not complete the three broader phases below.

### 1. Fix date contracts

Reading, editing, and Today are now separate for toolbar display and restoration. Next, decouple newer/older availability from spacer geometry, make distant jumps bidirectional, define future-day behavior, and introduce consistent localized date presentation with explicit storage identity.

Verify jumps into old, missing, and future days; scroll both ways to exact boundaries. Test midnight while reading away from Today, while editing, and during composition. Cover leap days, DST, wake after several days, backward clock changes, timezone travel, and non-Gregorian display preferences. Switching streams during a read must discard stale results.

### 2. Compose the interface

The visible-date control and contextual Today action replace the always-present Today/calendar pair. Quiet date headings, explicit disclosure behavior, shared typography roles, and native writing settings remain proposed. Preserve the breadcrumb and optional tabs.

Verify keyboard and VoiceOver access, full historical year labels, calendar written-day indicators, selection versus Today, and 320-point/narrow-window layouts. Check English, German, French, Japanese, and Arabic labels. Test 16-, 20-, and 24-point writing with headings, code, emoji, tables, and long lists. Font and width changes must preserve content and reading position.

### 3. Make retention and geometry predictable

Replace empty-day materialization with catalog-based slices. Extend the implemented logical restoration contract across history paging, add Back history, unify height ownership, move file work off the main thread, and enforce byte/layout budgets.

Benchmark ten years of sparse and dense metadata, many medium notes, and isolated 10k/100k-line notes. Measure cold jump latency, frame stalls, retained bytes, and native input latency separately, in release builds. Report p50/p95 and the machine/fixture; compare against the existing renderer baseline. Include resize, source-mode toggles, images loading, collapsing days, external edits above the viewport, and reopen after typography changes. Document-count tests alone are insufficient.

## Reference patterns

- [Apple fonts](https://developer.apple.com/documentation/technologyoverviews/fonts): system UI fonts and document-content fonts have different roles. Use platform font APIs for UI adaptation.
- [Bear typography](https://bear.app/faq/typography-options/): writing font, size, line width, line height, and paragraph spacing are useful controls, but do not need to be permanent editor buttons.
- [iA Writer settings](https://ia.net/writer/support/basics/settings): constrained line-length choices and reduced surrounding controls support a focused reading surface.
- [Apple Notes](https://support.apple.com/guide/notes/view-your-notes-apd8b73d28be/mac): native settings and text zoom are preferable to adding another formatting strip.
- [Day One timeline](https://dayoneapp.com/guides/day-one-for-mac/journal-views-in-day-one-for-macos/) and [calendar](https://dayoneapp.com/guides/tips-and-tutorials/calendar-view-in-day-one/): separate chronological written content from access to all dates.
- [NotePlan command bar](https://help.noteplan.co/article/94-part-5-find-notes-with-the-command-bar): direct and natural-language date entry can share a retrieval surface.
- [NotePlan typography](https://help.noteplan.co/article/44-customize-themes): body and headings can follow editor font preferences while detailed theme spacing remains advanced.
- [NotePlan history](https://help.noteplan.co/article/63-part-3-project-notes-and-backlinks): documents Back/Forward through Project Notes. Current's reading-anchor contract is separate; it is not an attributed NotePlan feature.
- [Obsidian Daily Notes](https://obsidian.md/help/plugins/daily-notes): stable date-named note identity and a direct Today action. Its core documentation does not establish an infinite stream or a built-in calendar.

The visible-date toolbar and workspace source anchors are Current implementations. The sparse-stream contract and remaining navigation work are proposals. Neither status claims that the reference apps implement this same architecture.
