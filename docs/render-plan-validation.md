# Render-plan caching

September 28, 2026. This change keeps Current's daily timeline, Markdown files,
per-day editor sessions, and TextKit 1 layout manager.

## Pipeline

The parser still reads the complete note once per source revision. The renderer
now keeps a separate attributed source as its plan, without a layout manager.
Source lines are independent plan blocks except for fenced code, tables, and
images, which need their complete source range to render correctly.

Character edits mirror into that plan with UTF-16 offsets. Blocks touching an
edit are discarded; later blocks retain their plans at shifted offsets. Cache
entries also track selection reveal state and compact heading separators.
Changing a fence can affect text beyond the locally edited block, so obsolete
fence and rich-block extents are revisited after parsing.

Adjacent cache misses are planned together using the existing highlighter.
Planning preserves its ordered font/indent calculations and native font
fallback. Each requested source line is then compared against the actual editor
attributes. Only differing lines are written to native text storage. A cache
hit skips planning, but still compares actual attributes because paste, undo,
and AppKit can modify them independently.

Font configuration, source mode, table width, document URL, stream-link targets,
and asynchronous image completion invalidate plans. Image blocks also recheck
the existing file-metadata cache on each requested pass, including images that
were previously missing. Cached plans are limited to the current note, with no
extra document-history cache.

Character changes advance the geometry revision even when their attributes are
identical, including composition commit and clearing the note. Decorations still
run in TextKit's post-edit callback before its layout notification. This avoids
reintroducing stale glyphs or changing native selection/undo behavior.

## Additional fixes

Restoring an opening code fence previously left later paragraphs and tables with
code attributes. The new regression compares those edits with a fresh editor and
requires the old unclosed fence's entire extent to be restyled.

A native width change could reflow NSTextView without notifying SwiftUI of the
new row height, clipping the caret at the bottom of a long note. The editor's
scroll view now coalesces width-change measurements after native tiling.

## Validation

The complete package passes 120 tests plus `CurrentFeatureChecks` on macOS 26
using Swift 6.3.3 and Command Line Tools. Thirteen new regressions cover cache
reuse, shifted offsets, fence reclassification, heading separators, tables,
configuration changes, Unicode, undo, composition, long notes, and native
width-only resizing. The render tests compare actual glyph identities, glyph
properties, source offsets, attributes, and line geometry with a fresh editor.

Entering or leaving a 1,000-line fenced code block now restyles exactly its two
boundary lines, without another parse. For text and tables, repeating decoration
with unchanged source and context builds no new plans and writes no line attributes. A local
edit retains downstream cached plans at their shifted source offsets.

The matched optimized builds used a 1,012-line, 45,862-UTF-16-unit fixture at
1200 × 800 in dark mode. Both passed 28 native checks, including paste, undo,
composition, resizing, large scroll distances, and a 130-day history with at
most 60 days retained.

The 820 × 640 run also passes all 28 checks, including the resize/caret gate
that failed twice in the frozen baseline. Its median input plus layout is
7.41 ms, with a 228.61 MiB final footprint.

| Measurement | Before | After |
| --- | ---: | ---: |
| Median native input plus forced layout (38 calls) | 7.31 ms | 7.68 ms |
| 95th percentile | 11.88 ms | 8.44 ms |
| Maximum | 23.77 ms | 16.20 ms |
| Native paste call | 11.63 ms | 10.13 ms |
| Process footprint at mount | 250.53 MiB | 309.72 MiB |
| Process footprint at completion | 225.81 MiB | 235.22 MiB |

This single matched run shows fewer slow calls, a slightly higher median, and
extra memory for planning. It does not establish an overall speedup. The
deterministic improvement is reduced native attribute work, demonstrated by the
two-line fence test. Fixtures use temporary libraries; user note files are not
test fixtures.

The probe records a specific limitation for the native breadcrumb menu:
in-process accessibility activation can enter AppKit menu tracking, so that
interaction must be checked through the separately launched app. The skipped
interaction is not counted as a passing check. Bare `NSHostingView` also cannot
verify scene-level toolbar hiding in focus mode.

The rebuilt app was checked separately through native UI automation: the
breadcrumb menu opened, Switch Stream opened its sheet, and Journal opened its
writing fixture. Unicode heading paste rendered correctly and native undo
restored the source. Both QA and preview app logs were empty. The running
preview was then updated, restored its selected TPRM stream, and retained all
11 note files with identical hashes across shutdown and relaunch.

This is not an incremental parser or a TextKit 2 migration. Current still lays
out a complete daily note for stable timeline height, and virtualizes the
timeline by day. Native insertion timings include forced TextKit layout but
exclude subsequent screen display; they are not frame-rate measurements.
