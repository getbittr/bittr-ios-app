# Widget still capture runbook — BIT-76

**Mac-only.** Four stills of `BittrWidget` that settle the three questions
`shared/docs/widget-spec.md` §6 cannot answer from source. Batched into the single Mac
sitting ordered on BIT-14 — one checkout, one build.

**Time at the keyboard: about 3 minutes** (Tier A). Tier B is optional and adds ~10.

> **Read §6 of `widget-spec.md` first.** Two of the three questions are now reduced to
> *measurements with predicted values*, not judgement calls. You do not have to decide
> whether a font "looks like Gilroy" — capture the tile, and the numbers in §6.4 decide it.

---

## What changed versus the original ask

The BIT-76 description asked for a fresh install in airplane mode to reach the `N/A`
state. **That is not necessary.** `N/A` is just a `SimpleEntry` field value, and the
`#Preview` block at the bottom of `BittrWidget.swift` renders arbitrary entries through
the real WidgetKit harness without ever touching the network. The preview timeline in
that file now carries all four states explicitly, so the whole capture is: open one file,
resume the canvas, screenshot it twice per appearance.

No fresh install. No airplane mode. No cache clearing. No adding the widget to a home
screen (unless you want Tier B).

---

## Tier A — the canvas (settles §6 items 1, 2 and 3)

1. Open `ios/bittr.xcodeproj`.
2. Select the **BittrWidgetExtension** scheme and any iPhone simulator destination.
   **Write down which simulator you picked** — the answer to item 2 depends on the tile's
   point size, which depends on the device. See the table in §6.4 of `widget-spec.md`.
3. Open `ios/BittrWidget/BittrWidget.swift` and resume the canvas (**⌥⌘P**).
   The `#Preview(as: .systemSmall)` block is annotated with the four states; the canvas
   shows a timeline scrubber to move between them.
4. For each of the two states below, and in **both** appearances (the canvas appearance
   switcher, or Editor → Canvas → Color Scheme):

   | File name | Preview timeline entry |
   |---|---|
   | `widget-light-populated.png` | entry 1 — `€ 94.250` |
   | `widget-dark-populated.png`  | entry 1 — `€ 94.250` |
   | `widget-light-na.png`        | entry 3 — `€ N/A` |
   | `widget-dark-na.png`         | entry 3 — `€ N/A` |

   Capture with **⇧⌘4** and drag a box around the tile. Two rules, both of which matter
   for the measurement to work:

   - **The whole tile must be in frame, all four corners.** The measurement is a *ratio*
     against the tile width, so canvas zoom does not matter — but a cropped tile makes it
     unrecoverable.
   - **Do not scale or re-encode the PNG** afterwards.

5. Drop the four files in **`shared/docs/device-checks/widget/`** (not
   `shared/docs/screenshots/` — see the note in that directory's README; four stills no
   flow can produce will be reported as `orphaned` by `screenshot_map.py --verify`).
6. Commit, and comment the simulator model on BIT-76. That is the whole job — the
   numbers get read off the PNGs and written into `widget-spec.md` §6.

## Tier B — the real home screen (optional)

Tier A renders through WidgetKit at the correct family size, so it answers all three §6
questions. Tier B adds only what a preview cannot show: the real container corner radius,
how `containerBackground` interacts with the full-bleed `ContainerRelativeShape`, and
whether the `.padding(-20)` overflow described in `widget-spec.md` §4.1 visibly clips the
price at the tile edges.

1. Run the **bittr** scheme on the simulator once, so the widget extension is installed.
2. Long-press the home screen → **+** → search "Bittr" → add the small widget.
   The gallery entry itself is a capture worth having (`snapshot(for:in:)` hard-codes
   `94.250`).
3. Capture at native scale — **not** ⇧⌘4, which captures at Mac screen scale:

   ```sh
   xcrun simctl io booted screenshot ~/Desktop/widget-home-light.png
   ```

4. Dark mode: Settings → Display & Brightness → Dark, then capture again.
5. Name these `widget-home-<light|dark>.png` and put them in the same directory. Note the
   simulator model in the commit message — a native-scale capture pins the point size
   exactly, so these are the measurement-grade artefacts.

`N/A` on a real home screen needs no cache **and** a failed fetch, which the simulator has
no airplane-mode switch for. Do not chase it: Tier A already has both `N/A` stills.
Note also that a **Debug** build reads `https://staging.getbittr.com/api` via
`BittrAPIEnvironment` — and staging *does* serve `/price/btc` (verified 200), so a debug
build shows a real price rather than `N/A`.

---

## Provenance

These are **manually captured stills, not Maestro output, and iOS-only.** Maestro cannot
drive the iOS home-screen widget surface or the Xcode canvas, so no flow will ever
regenerate them. `shared/docs/device-checks/widget/README.md` records that on disk next to
the files.
