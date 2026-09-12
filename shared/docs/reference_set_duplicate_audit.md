# Reference-set duplicate audit — 2026-09-09 capture (274 shots)

Ran a pixel-hash comparison over all 274 landed screenshots to find pairs that
are byte-identical. Most duplicates are legitimate — the same screen captured
from different flows (Home appears 6×, the PIN unlock screen 9×). Those are
fine and expected.

What matters are **within-flow pairs that are supposed to show a state change**
and don't. Those read as covered in the reference set but contain no new
information. Four cases:

| Pair | Cause | Status |
|---|---|---|
| `bitcoin_map/07_map_moved` = `08_back_to_user` | missing animation wait | ✅ **fixed** |
| `bitcoin_value/05_after_scrub` = `04_value_loaded` | structural — not capturable | ⚠️ answered from source instead |
| `bitcoin_value/03_value_loading` = `04_value_loaded` | timing race | ⚠️ open |
| `onboarding/18` = `19`, `buy_signup/09` = `10` | no scroll needed on this device | ℹ️ not a bug on iPhone 16 Pro |

## 1. `bitcoin_map/07_map_moved` = `08_back_to_user` — fixed

`assertVisible: map.mapView` was standing in as a wait after the
user-location tap, but the map view is on screen for the entire flow, so the
assert passed instantly and the screenshot fired before MKMapView's animated
camera move had run. The swipe immediately above already had a
`waitForAnimationToEnd` for exactly this reason; the tap did not.

Added the matching wait (`features/bitcoin_map.yaml`). The re-center is a real
app behaviour that simply was never photographed — this needs a Mac re-run of
`bitcoin_map.yaml` to produce a genuine `08`.

## 2. `bitcoin_value/05_after_scrub` = `04_value_loaded` — not capturable, spec'd from source

**This is not a missed swipe.** The flow already anchors the gesture to
`value.graphView` rather than screen percentages, and the comment at
`features/bitcoin_value.yaml:82` records that the earlier percentage-based
version was fixed precisely because it landed below the plot.

The scrub card cannot survive a screenshot, for two independent reasons in
`GraphView.swift`:

- `touchesEnded` (line 62) removes every `"valuecard"` subview on finger-lift.
- `showGraphValue` (line 85) rebuilds nothing when `recognizer.state == .ended`.

Maestro's `swipe` is one atomic command; no `takeScreenshot` can interleave
with it. So `05_after_scrub` is by construction a picture of the screen *after*
the card is gone, and it will be identical to `04_value_loaded` on every future
run. It should be **retired from the reference set**, not re-chased.

### Q-08 answered: the readout exists, and here is its full spec

`GraphView.showGraphValue` builds the card entirely in code, so it can be
specified without a photograph:

**Card** — `UIView`, 80 × 40 pt, `backgroundColor .white`, `cornerRadius 8`,
`alpha 1`, `layer.zPosition 10`.

Positioning tracks the finger in both axes:
- **x**: `centerX` = graph `leading` + `actualX + 30`, where `actualX` is the
  touch x minus 30, clamped to `[0, graphWidth - 60]`. So the card stops 30 pt
  from either edge instead of running off.
- **y**: `bottom` = graph `bottom` − `(30 + priceRelativeToSpan × (graphHeight − 30))`,
  where `priceRelativeToSpan` is the point's price normalised into the
  visible min/max span (`0.5` when the span is zero). The card rides up and
  down with the price line.

**Two centred labels**, stacked:
- Date — `Gilroy-Regular 10`, black at `alpha 0.4`, 9 pt from card top.
  Format `dd MMM yyyy` (e.g. `07 Sep 2026`).
- Price — `Gilroy-Bold 12`, black, 3 pt below the date label. Carries
  `accessibilityIdentifier value.graphValueLabel`. Text is
  `"<currency> " + formatEuroValue(Int(price))` — currency code, space,
  thousands-separated integer, no decimals.

So `value.graphValueLabel` being a distinct id from the price label was the
right read: there is a live readout, it is a floating card, and it is
gesture-scoped.

## 3. `bitcoin_value/03_value_loading` = `04_value_loaded` — open

Not previously reported: the *loading* state is also missing, making this a
three-way collision, not a pair.

`03` is taken right after `assertVisible: value.graphView`, which resolves as
soon as the view exists — before the price fetch resolves. It is meant to show
the spinner. In this run the graph was already fully drawn by then, so the
"loading" shot is really a second copy of the loaded state.

`bitcoin_value.yaml` is explicitly non-destructive and re-runnable, so warm
price data is likely — meaning this will reproduce. Capturing a true loading
state needs a wait on the spinner *appearing* (`value.valueSpinner`) before the
screenshot, rather than on the container view existing. Left unchanged for now
because it trades a reliable shot for a racy one; worth a decision.

Same shape as `bitcoin_map/03_map_loading` = `04_places_loaded`, which is the
identical pattern in the map flow.

## 4. `onboarding/18` = `19` and `buy_signup/09` = `10` — device-dependent, not a bug

Both pairs are `takeScreenshot` → `scrollUntilVisible(transferInfo.nextButton)`
→ `takeScreenshot`. On the 1206 × 2622 iPhone 16 Pro the "Let's go" button is
already on screen, so `scrollUntilVisible` is a no-op and "bottom" equals "top".

The flow is correct; there is simply no distinct bottom state on a device this
tall. Worth flagging for the Android port: on a shorter viewport the scroll
*will* happen and the two shots will diverge, so a parity diff against this
reference set would show a false mismatch. That belongs in the deviation
register rather than in a flow fix.
