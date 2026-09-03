# Design QA — Mushaf page

Source visual truth: `/Users/user/Downloads/230x498bb.webp`

Implementation screenshot: unavailable from this automation environment.

Viewport and state: macOS Flutter reader; the rebuilt app launched successfully, but this environment cannot capture its Metal-rendered application window. The earlier user screenshot is a pre-change capture and is not valid implementation evidence.

Source dimensions: 230 × 498 px.

Implementation dimensions / density normalization: unavailable.

Full-view comparison: blocked — a current implementation screenshot could not be captured and therefore cannot be placed alongside the source visual.

Focused-region comparison: blocked for the same reason. The main regions to compare are the floral frame, left margin notes, and Qur'an text column.

**Findings**

- [P1] Current rendered evidence is unavailable.
  Location: macOS reader page.
  Evidence: the Flutter build and static analysis pass, but a macOS screen-capture attempt could not create a display image.
  Impact: the ornamental frame and responsive text layout cannot be honestly signed off visually.
  Fix: capture the updated reader at page 312 and compare it against the source at a matched crop.

**Implementation Checklist**

1. Launch the app and open page 312 in the Shubah reader.
2. Confirm the floral frame remains visible and the left callout margin does not overlap Qur'an text.
3. Confirm the two callouts show `حفص: طه / شعبة: طٜهٜ` and `حفص: رأى / شعبة: رٜءٜا`.

Comparison history: initial QA cannot start because no post-change capture is available.

final result: blocked
