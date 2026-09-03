# Design QA — مصحف القراءات

Source visual truth:

- `/var/folders/lp/r5d84wfs49z10nsh51444k_c0000gn/T/codex-clipboard-c6120b22-23d8-40c6-bcdd-443f609480e1.png`
- `/var/folders/lp/r5d84wfs49z10nsh51444k_c0000gn/T/codex-clipboard-5e0e888c-2eec-4082-b54c-ca4e2099c4d7.png`

Implementation screenshots:

- `/Users/user/Desktop/quran/test/goldens/reader_rtl.png`
- `/Users/user/Desktop/quran/test/goldens/reading_sheet_rtl.png`
- `/Users/user/Desktop/quran/test/goldens/differences_drawer_rtl.png`

Combined comparison evidence:

- `/Users/user/Desktop/quran/test/goldens/design_comparison.png`
- `/Users/user/Desktop/quran/test/goldens/reading_sheet_comparison.png`

Viewport and normalization: Flutter mobile viewport `430 × 932` logical pixels at device pixel ratio `1`. The `1002 × 2048` source captures were aspect-fitted and center-cropped to `430 × 932` before being placed beside the implementation. The implementation captures are native `430 × 932` PNGs.

State: RTL light theme, Quran reader open, Shubah selected as the primary reading. Additional captures cover the reading selector and the right-side page-differences drawer.

## Findings

No actionable P0, P1, or P2 visual mismatch remains for the requested product scope.

- Fonts and typography: Arabic UI text uses the bundled Noto Sans Arabic font. Reading text uses the selected riwayah font. RTL shaping, hierarchy, wrapping, and small labels are legible at the target viewport.
- Spacing and layout rhythm: the reader now uses inset rounded green top and bottom controls, a large uninterrupted paper area, consistent horizontal margins, and no two-column squeeze.
- Colors and visual tokens: the green, warm paper, white, and muted gold palette follows the reference. Selection and active states remain distinguishable with sufficient foreground contrast.
- Image quality and asset fidelity: there are no raster placeholders or improvised visible assets. The application uses Flutter's vector icon font and the bundled Quran fonts; the golden fixture intentionally exercises layout with Unicode Arabic text.
- Copy and content: the app name is `مصحف القراءات`; reading names and page-difference labels are concise Arabic copy. The main screen keeps the primary reading visible and moves comparisons into the drawer as requested.

## Open Questions

- The source app exposes more general navigation and playback controls. Their omission is intentional because this version is scoped to offline reading, reading selection, page navigation, swipe navigation, and page differences.
- The source selector displays surahs, while this product's bottom selector displays riwayat because that is the requested interaction.

## Full-view comparison evidence

The combined main-screen comparison confirms the same broad composition: Quran content dominates the viewport, controls are green and inset, the page is white, and navigation remains anchored at the top and bottom. The implementation deliberately uses fewer controls and adds a clear gold reading selector.

## Focused-region comparison evidence

The reading-sheet comparison verifies the dimmed background, warm sheet surface, green selected state, rounded list items, RTL labels, and reachable selection targets. The separate drawer capture verifies that page differences open from the right and name both Hafs and the selected comparison reading.

## Comparison history

1. Earlier implementation evidence showed a rigid two-column reader with narrow Quran text, excessive empty space, and inline differences. The reader was rebuilt around a full-width primary text page, bottom reading selector, and a separate differences drawer.
2. The first post-build golden capture exposed missing Material icon glyphs in the test renderer. The Material Icons font was loaded explicitly for golden tests, then all captures were regenerated.
3. The first layout fixture was too sparse to judge page density. The fixture was expanded, the main capture regenerated at the same viewport, and the final side-by-side comparison showed stable wrapping with no clipping or overlap.

## Implementation Checklist

- [x] Global RTL direction.
- [x] App opens directly on the main reading.
- [x] Bottom reading selector changes Hafs, Shubah, and Qalun offline.
- [x] Swipe changes pages.
- [x] Right-side drawer shows only the differences on the current page.
- [x] Responsive mobile layout has no overflow at `430 × 932`.
- [x] Golden tests cover the reader, reading selector, and differences drawer.
- [x] Flutter analyzer and full test suite pass.

## Follow-up Polish

- [P3] A later version can add more of the reference app's optional controls, such as search, bookmarks, audio, and surah navigation, without changing the current reader architecture.

final result: passed
