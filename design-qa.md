# Design QA — عرض صفحة المصحف

Source visual truth:

- `/Users/user/Library/Containers/ru.keepcoder.Telegram/Data/tmp/IMAGE 2026-09-05 17:44:37.jpg` — صفحة مصحف كاملة بهوامش ضيقة و15 سطرًا.
- `/Users/user/Library/Containers/ru.keepcoder.Telegram/Data/tmp/IMAGE 2026-09-05 17:44:38.jpg` — صفحة بلون ورقي وعناوين السور داخل فاصل زخرفي.
- `/Users/user/Library/Containers/ru.keepcoder.Telegram/Data/tmp/IMAGE 2026-09-05 17:44:42.jpg` — قارئ هاتف مع شريط علوي وسفلي.

Implementation screenshot:

- `/Volumes/main/projects/quran/test/goldens/hafs_madani_page_3.png`

Viewport and normalization:

- Flutter viewport: `430 × 932` logical pixels, device pixel ratio `1`.
- Source #7: `626 × 1280` pixels. It was aspect-fitted and center-cropped to `430 × 932` for comparison.
- Implementation: native `430 × 932` pixels.
- Combined evidence: `/Users/user/Desktop/quran/test/goldens/mushaf_reference_comparison.png`.
- Focused text evidence: `/Users/user/Desktop/quran/test/goldens/mushaf_text_comparison.png`.

State: RTL light theme, Hafs selected, Madani page 3, top and bottom reader controls visible.

## Findings

No actionable P0, P1, or P2 mismatch remains in the requested reading-page scope.

- Fonts and typography: Quran lines and basmala now use the bundled KFGQPC HAFS Uthmanic Script v18 (`UthmanicHafs`). Its Unicode cmap covers every character in the 604-page layout, including diacritics and stop marks. Each source line is measured using the same font as the renderer and receives the largest size that fits its fixed width and height. Source verse numbers use the font's own ornaments without an extra end-of-ayah glyph. `HafsSmart` remains available for the original PUA data, and Noto Sans Arabic remains the UI font.
- Spacing and layout rhythm: the previous elevated card, page-title block, divider, and broad margins were removed. The page now uses a fixed 15-slot Madani grid with narrow 10 px side margins, a compact metadata row, and a small centered page number. Top and bottom controls were reduced to preserve more reading area.
- Colors and visual tokens: warm paper, black Quran text, muted metadata, gold surah treatment, and green navigation follow the reference family while retaining the app's existing reading-comparison identity.
- Image quality and asset fidelity: there are no raster placeholders or improvised decorative illustrations. Quran text and icons render as fonts/vectors. The ornate surah ornaments in one reference were intentionally reduced to a restrained bordered band because no licensed matching ornament asset is bundled.
- Copy and content: the page identifies the surah and `حفص عن عاصم` without adding explanatory copy inside the Mushaf area.

## Full-view comparison evidence

The combined image verifies the same dominant composition: edge-to-edge Quran page, dense fixed lines, very small page metadata, and anchored navigation. The implementation reserves slightly more vertical room for comparison/navigation controls but keeps all 15 Quran lines visible.

## Focused-region comparison evidence

The updated page-3 golden verifies Arabic shaping, diacritics, line baselines, inline ayah ornaments, horizontal fill, and the absence of clipping with the Uthmanic font. Earlier comparison collages document the previous Noto Sans Arabic rendering and are historical evidence, not previews of the current font.

## Comparison history

1. Earlier implementation used a white elevated card with 14–22 px outer/inner padding, a redundant `صفحة` title and divider, fixed 38 px lines, and scrolling. This reduced the Quran area and could make the page feel unlike a Mushaf.
2. The page was changed to a warm edge-to-edge surface, a fixed 15-line grid, adaptive per-line font measurement, 10 px margins, compact metadata, and smaller controls.
3. Post-fix full and focused comparisons show every line in its source position with no wrap, overflow, or clipped diacritics.

## Implementation Checklist

- [x] Fixed 15-line page geometry.
- [x] Per-line adaptive font size with width and height constraints.
- [x] No text outside the Mushaf page.
- [x] Narrow page margins and no card/shadow.
- [x] Compact surah/reading metadata and page number.
- [x] Reduced top and bottom chrome.
- [x] Golden coverage at `430 × 932`.
- [x] Full-view and focused visual comparison.

## Uthmanic font verification

- PASS: Unicode coverage checked against all text in the bundled 604-page layout; no missing characters.
- PASS: updated page-3 golden reviewed at `430 × 932`; all 15 lines fit, with diacritics and a single ornament per ayah number.
- PASS: golden interaction checks still open word comparison and toggle reader controls.
- Typeface purpose: the user requested the Mushaf's Uthmanic script. Existing paper, navigation, and layout direction are retained; this change introduces no new decoration or motion.

final result: passed
