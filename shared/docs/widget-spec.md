# Widget spec — `BittrWidget` (iOS) → Glance widget (Android)

**Status:** decided · **Decided by:** Head of App (Android), BIT-11 · **Source of truth:** `ios/BittrWidget/*` at `c297ed1`

This is the porting spec for the iOS home-screen widget. It exists because the widget
is absent from the BIT-3 screenshot catalog and cannot be added to it: Maestro cannot
drive the iOS home-screen widget surface, so no flow can reach it. This document replaces
the screenshot as the design input and behavioural spec for the Android port.

---

## 1. Decision

**In scope for the port — out of scope for the v1 done-gate.**

The port's v1 definition of done is "the iOS Maestro suite passes on Android". The widget
has no Maestro flow and cannot have one, so by construction it cannot be part of that gate.
It is not dropped: `ANDROID_PORT_PLAN.md` already schedules it as Phase 4 item 11
("Glance widget (mirrors `BittrWidget`)"), which is well after the gate. That ordering stands.

**Specification route: from source (option 3), not manual capture and not XCUITest.**

The widget is a single `.systemSmall` family rendering one ~40-line declarative SwiftUI view.
Every font, size, padding and colour is a literal in `BittrWidget.swift` and the asset catalog.
For this surface the source is a *better* spec than a screenshot — it gives exact values
instead of requiring someone to measure pixels — so "accepting no visual reference" costs
almost nothing here. Concretely the whole surface is **four renderings** (1 size × 2 data
states × light/dark).

An XCUITest target was rejected as disproportionate: it needs a Mac, a separate CI lane and
ongoing maintenance, to produce four images for a surface that is not in the v1 gate.

Manual capture was rejected **as the primary route** but is retained as a cheap cross-check —
see §6, which lists the three things source alone cannot settle. That check is a few minutes
of the founder's time and is *not* a blocker for the Android implementation.

This call is reversible and cheap to reverse. If the founder wants the widget in the v1 gate,
or wants stills first, say so on BIT-11 and the Phase 4 ordering changes — nothing here is
sunk cost.

---

## 2. What the widget actually is

A **public bitcoin-price ticker**. It is fully autonomous: it does its own HTTP fetch, keeps
its own cache, and the app never talks to it (there is no `WidgetCenter.reloadTimelines` call
anywhere in the iOS codebase).

It touches **no user data at all** — no wallet, no balance, no account, no auth. It fetches
`GET https://getbittr.com/api/price/btc` and renders the number.

> The BIT-11 ticket asked for "the logged-out / no-wallet state" to be enumerated.
> **That state does not exist.** The widget renders identically whether the user has a wallet,
> is signed out, or has never onboarded. There is nothing to design for it. Anyone porting
> this should not go looking for an empty/signed-out variant.

---

## 3. States — the complete enumeration

### 3.1 Families (sizes)

Exactly one: **`.systemSmall`**. Declared at `BittrWidget.swift` `supportedFamilies([.systemSmall])`.

No medium, no large, no lock-screen accessory families, no StandBy variant, no Watch.
Android should ship **one** Glance size cell and resist the temptation to add a resizable widget
— matching iOS means one small square.

### 3.2 Data states

The rendering is fully determined by `SimpleEntry`. There is one layout; only the value string
and the currency glyph change.

| # | State | Renders | Reached when |
|---|---|---|---|
| 1 | **Populated** | `€ 94.250` | Fetch succeeded, **or** fetch failed but a cache exists |
| 2 | **No data** | `€ N/A` | No cache **and** the fetch failed (first install, offline) |
| 3 | **Placeholder** | `€ N/A` | WidgetKit redacted/skeleton rendering — `placeholder(in:)` |
| 4 | **Gallery preview** | `€ 94.250` | The add-widget picker — `snapshot(for:in:)`, a hard-coded literal |
| 5 | **Malformed payload** | `€ 0` | API returned a non-numeric string; `formatEuroValue` falls back to `"0"` |

States 2 and 3 are **visually identical**, as are 1 and 4. So there are **two distinct
renderings**: a number, or `N/A`. State 5 is a degenerate case of state 1 and is worth
knowing about because `€ 0` looks like a real price rather than an error — see §7.

### 3.3 Currency variants

`€` or `CHF`, selected by `UserDefaults.standard["currency"] == "CHF"`, picking `chfValue`
over `eurValue`. When CHF, both the inline prefix and the bottom-right glyph read `CHF`.

**In the shipped iOS app this is always `€`.** See §7.1 — the CHF branch is unreachable.

### 3.4 Appearance

Light and dark, via asset-catalog `luminosity` variants. Both the colours and the piggy icon
swap. Follows the system appearance, not the app's in-app dark-mode setting (an extension
cannot see the app's preference without a shared container, which does not exist here).

**Total distinct renderings to design: 4** — {number, `N/A`} × {light, dark}.

---

## 4. Visual spec

All values are literals from `BittrWidget.swift` / `Assets.xcassets`.

### 4.1 Structure

```
ZStack
├── ContainerRelativeShape().fill(YellowOrDark2)     ← full-bleed background
└── VStack (aligned .top, maxHeight .infinity)
    ├── HStack  (maxWidth .infinity, .top; padding top 20)
    │   ├── Image "iconpiggy" — resizable, scaledToFit, 16×16
    │   │        padding: leading -3, trailing 1
    │   └── Text "bitcoin value" — Gilroy-Bold 16, WhiteOrYellow
    │            padding top 3, lineLimit 1
    ├── Spacer
    ├── Text "<currency> <value>" — Gilroy-Bold 42, BlackOrWhite
    │        minimumScaleFactor 0.5 (floor ≈ 21pt), lineLimit 1
    │        padding: horizontal (default), top 6, leading 3, trailing 3
    ├── Spacer
    └── HStack
        ├── Spacer
        └── Text "<currency>" — Gilroy-Bold 18, WhiteOrYellow
                 padding: trailing 23, bottom 20
```

Outer modifiers: `.padding(-20)` then `.widgetURL(widget-deeplink://)`, with
`.containerBackground(.fill.tertiary, for: .widget)` applied by the configuration.

Net effect: the currency glyph appears **twice** — once as a prefix on the big number
(`€ 94.250`) and once alone in the bottom-right corner. That is intentional in the current
design; mirror it.

**The price gets more width than the tile has.** The `.padding(-20)` proposes `tile + 40`
to the content, and the price's own insets take 19 per side (`.padding(.horizontal)` = 16,
then leading/trailing 3), leaving it **`tile + 2`pt** of layout width — about 1pt bleeding
past each visible edge, clipped by the container. So the price is effectively full-bleed
horizontally with no side margin, and `minimumScaleFactor` is fitting to `tile + 2`, not to
`tile − 38`.

> **Porting trap.** An Android widget that reads §4.1 literally and applies a 19dp
> horizontal inset gives the price **40dp less** width than iOS does, so Glance's autosize
> lands several points smaller and the tile looks visibly different at the same price. Give
> the price the full cell width. See §6.2 for the numbers this changes.

### 4.2 The negative padding

`.padding(-20)` expands the content 20pt beyond the widget bounds on every side, so the
`ContainerRelativeShape` fill covers the whole tile and overrides the system
`containerBackground`. The inner `padding(.top, 20)` / `padding(.bottom, 20)` exist to
compensate for it.

**Do not port this literally.** It is a workaround for a WidgetKit-specific layout rule, not a
design intent. In Glance, just fill the container and use 20dp top/bottom insets directly.

### 4.3 Colours

Asset-catalog colours are authored in **Display P3**, which is *not* what a Compose `Color(0xFF…)`
literal means. The P3 values below are authoritative; the sRGB column is the computed
conversion to use in Android source.

| Token | Mode | Display P3 | sRGB (use this on Android) | Used for |
|---|---|---|---|---|
| `YellowOrDark2` | light | `#EFC95D` | `#F7C744` | Background |
| `YellowOrDark2` | dark | `#4B648D` | `#446591` | Background |
| `WhiteOrYellow` | light | `#FFFFFF` | `#FFFFFF` | "bitcoin value" label, corner glyph |
| `WhiteOrYellow` | dark | `#EFC95D` | `#F7C744` | "bitcoin value" label, corner glyph |
| `BlackOrWhite` | light | `#000000` | `#000000` | The big price number |
| `BlackOrWhite` | dark | `#FFFFFF` | `#FFFFFF` | The big price number |

All six convert in-gamut, so no clipping judgement is needed. Note the dark background is a
**slate blue**, not a dark yellow — the token name (`YellowOrDark2`) is misleading, and it is
easy to assume otherwise and get it wrong.

`WidgetBackground.colorset` exists in the widget's asset catalog but is an empty Xcode
template and is referenced nowhere. Ignore it; do not port it.

### 4.4 Assets

- **Icon** — `iconpiggy`, 16×16pt, @1x/@2x/@3x. Light mode uses `iconpiggywhite*.png`;
  dark mode uses `iconpiggyyellow*.png`. Source: `ios/BittrWidget/Assets.xcassets/iconpiggy.imageset/`.
- **Font** — Gilroy-Bold (`ios/Gilroy-Bold.ttf`), bundled into the widget target and declared
  in the widget's own `Info.plist` `UIAppFonts`. Android needs the same file as a font resource
  in the widget's module.

### 4.5 Copy

Only two literal strings render: **`bitcoin value`** (lowercase, exactly as written) and the
currency glyph. Neither is localised on iOS — they are bare Swift string literals, not
`NSLocalizedString`. The widget gallery entry adds two more, which *are* user-visible and also
need porting:

- Display name: **"Bittr bitcoin value"**
- Description: **"See bitcoin's current value at a glance on your home screen."**

---

## 5. Behaviour spec

### 5.1 Data source

`GET https://getbittr.com/api/price/btc` — no auth, no parameters.

Response JSON, with the rates as **strings, not numbers**:

```json
{ "btc_eur": "94250.17", "btc_chf": "91003.42" }
```

The URL is **hard-coded to production** and bypasses `EnvironmentConfig` entirely, so a staging
build of the iOS app still shows production prices in its widget. See §7.2.

### 5.2 Formatting

`formatEuroValue` — `NumberFormatter`, `.decimal` style, `maximumFractionDigits = 0`,
`locale = .current`. So the price is rounded to whole currency units and the grouping separator
is locale-dependent: `94.250` in nl-NL/de-DE, `94,250` in en-US, `94 250` in fr-FR.
On a `Double(...)` parse failure it returns the string `"0"`.

The `94.250` in `snapshot(...)` and the `N/A` in `placeholder(...)` are **hard-coded literals**,
not run through the formatter — so the gallery preview always shows a dot separator regardless
of locale. Cosmetic, and only visible in the add-widget picker.

### 5.3 Refresh policy

`Timeline(policy: .after(...))`:

- fetch succeeded → next refresh requested at **+2 hours** (7200s)
- fetch failed → next refresh requested at **+30 minutes** (1800s)

These are *requests*; WidgetKit throttles at its own discretion. Android's Glance/WorkManager
scheduling differs — match the intent (2h nominal, 30min retry-on-failure), not the mechanism.

### 5.4 Cache

`UserDefaults.standard`, key `mostrecentwidgetdata`, an `NSDictionary` of four strings:
`date`, `formattedEurValue`, `formattedChfValue`, `preferredCurrency`.

`date` is formatted `"dd MMM yyyy HH:mm"` with the default locale; if the device locale changes
between write and read the parse fails and it silently falls back to "now". The cached `date` is
never rendered, so this is invisible to the user — but don't port the round-trip as if it mattered.

The cache is read *before* the network call and used as the entry if the call fails, so a
populated widget stays populated indefinitely while offline — it never reverts to `N/A`, and
**it never shows the user that the price is stale**. See §7.3.

### 5.5 Tap

The whole widget is one tap target: `.widgetURL(URL(string: "widget-deeplink://"))`.

Handling chain on iOS:
`SceneDelegate.launchBittrValue` matches scheme `widget-deeplink` →
posts `NSNotification "openvalue"` →
`HomeViewController.openValueVC` →
segue `HomeToValue` → **the Value (price chart) screen**.

On Android: tapping the widget opens the Value screen. Note the iOS path routes *through* Home,
so Home is beneath Value on the back stack — back from Value lands on Home, not on the launcher.
Match that.

---

## 6. What source cannot settle

Three things need eyes on a real device. None blocks starting the Android implementation.
Capture procedure: **`shared/docs/widget-capture-runbook.md`** (BIT-76), batched into the
single Mac sitting ordered on BIT-14.

Two of the three are no longer judgement calls. §6.4 predicts what each one should measure,
so the still is read rather than eyeballed. What §6.1–6.3 record is the state after the
2026-09-13 source pass; the *Answer* rows are what the stills fill in.

### 6.1 Item 1 — does the "bitcoin value" label render in Gilroy-Bold 16, or system title3?

Both small labels apply `.font(.custom("Gilroy-Bold", size:))` and then a second
`.font(.title3)` later in the same chain — the label (16) at `BittrWidget.swift:158`/`161`
and the corner glyph (18) at `:186`/`:189`. Note every intervening modifier
(`.fontWeight`, `.foregroundColor`) returns `Text`, so both `.font()` calls are the
`Text`-specific overload, not the environment one — which is why the usual
"innermost wins" rule for `.font()` on a container does not settle it.

**Settled from source: the font is available, so this is purely a modifier-precedence
question, not a silent-fallback one.** `Font.custom` falls back to the system font without
error when the family is not registered, which would have been a second, indistinguishable
cause. It is ruled out:

- `Gilroy-Bold.ttf` is in the **BittrWidgetExtension** target's own Resources build phase
  (`ios/bittr.xcodeproj/project.pbxproj` — that phase contains exactly one file, this one).
- The **widget's own** `Info.plist` declares `UIAppFonts = [Gilroy-Bold.ttf]`. An extension
  does not inherit the app's font registration, so this matters.

So `.font(.custom("Gilroy-Bold", size: 16))` resolves. Whether the later `.font(.title3)`
overrides it is what the still answers.

**Answer:** _pending the stills._

### 6.2 Item 2 — where the 42pt price lands under `minimumScaleFactor(0.5)`

Narrowed from "somewhere in 21–42pt" to a predicted value per device, from the Gilroy-Bold
advance widths and the layout arithmetic. **The 0.5 floor is never reached** — not even by
the worst case — so Android must not assume 21pt.

Available width for the price `Text` is **`tileWidth + 2pt`**, not tile-minus-padding:
`.padding(-20)` on the outer `ZStack` proposes `tile + 40` to the content, and the price
carries `.padding(.horizontal)` (16) plus `.padding(.leading/.trailing, 3)` = 19 per side.
See §4.1 — this is the single most consequential number for porting item 2.

Predicted rendered size (Gilroy-Bold advances, ±2% for kerning — the font has a `GPOS`
table):

| Tile | Device | `€ 94.250` | `€ 100.000` | `CHF 100.000` | `€ N/A` |
|---|---|---|---|---|---|
| 141pt | SE (320pt screen) | 36.0pt | 30.6pt | 24.0pt | 42pt |
| 155pt | iPhone 8 / SE2–3 (375pt) | 39.5pt | 33.6pt | 26.3pt | 42pt |
| 158pt | iPhone 14/15/16 (393pt) | 40.3pt | 34.3pt | 26.8pt | 42pt |
| 170pt | Pro Max (430pt) | 42.0pt (no scaling) | 36.9pt | 28.8pt | 42pt |

Two consequences for the capture, both in the runbook:

- **The `N/A` stills cannot answer item 2.** `€ N/A` is 114.5pt wide at 42pt, so it fits
  unscaled on every tile. Only a *populated* still measures the scale factor, and **which
  price it shows changes the answer** — `€ 94.250` and `€ 100.000` differ by 6pt.
- Which simulator was used must be recorded, since the answer is per-device.

**Answer:** _pending the stills._

### 6.3 Item 3 — is the dark-mode slate-blue background intended?

`YellowOrDark2` dark is `#4B648D` P3 / `#446591` sRGB — a slate blue behind a yellow label,
under a token name that reads as "yellow or dark *yellow*". Nothing in source can settle
intent; this is one confirming glance. Unlike items 1 and 2 it needs no measurement.

**Answer:** _pending the stills._

### 6.4 How to read the answers off a still

Both measurements are **ratios against the tile width**, so canvas zoom and capture scale
do not matter — only that all four tile corners are in frame. Gilroy-Bold is 1000 units/em,
cap height 700, x-height 500.

**Item 1** — measure the ink width of the string `bitcoin value`, and the tile width, in the
same pixels:

- `labelWidth / tileWidth ≈ 0.61` on a 158pt tile (96.4pt advance at 16pt) → **Gilroy-Bold
  16 won**; the chain is fine as written.
- materially larger, ≈0.7+ → **`.font(.title3)` won** and the label is the system font at
  ~20pt. Cross-check on height: the lowercase x-height is 8.0pt at Gilroy 16 versus ~10pt at
  title3 — a 25% difference, unmistakable at @2x or better. (`bitcoin value` has no
  capitals, so measure x-height off `v`/`u`, and ascender off `b`/`l`/`t`.)

The corner glyph `€` is the same question: 11.0pt advance and 13.1pt ink height at Gilroy
18, versus 12.2pt / 14.6pt if it renders at title3's 20pt.

**Item 2** — the digit glyphs are 0.714em of ink tall, so:

```
renderedPointSize = (digitInkHeight / tileWidth) × tileWidthInPoints / 0.714
```

At @3x on a 158pt tile (474px), a `9` measuring 86px of ink is 40.3pt; 73px is 34.3pt; 45px
would be the 21pt floor.

### 6.5 Provenance of the stills

They land in **`shared/docs/device-checks/widget/`**, not `shared/docs/screenshots/widget/`
as BIT-76 originally asked. `screenshots/` is the canonical BIT-3 reference set indexed from
the flow YAML; four stills no flow declares are reported there as `orphaned` and their
cropped size trips the single-size check (measured: `orphaned=4` there versus `orphaned=0`
under `device-checks/`). That directory's `README.md` records the manual, non-Maestro,
iOS-only provenance next to the files.

If the stills never arrive, the Android implementation proceeds on this document: items 1
and 2 have predicted values to build against, and item 3 is a design-review question.

---

## 7. Defects found while writing this

These are iOS bugs found by reading the source for this spec. They are **not** the Android port's
to inherit — the Android widget should be built correct. Tracked separately; listed here so the
next person to read this file doesn't re-derive them.

### 7.1 The CHF branch is dead — the widget always shows euros

`BittrWidget.swift` reads `UserDefaults.standard.value(forKey: "currency")` to pick CHF. But:

- The widget is an **app extension**, so `UserDefaults.standard` resolves to the *extension's own*
  container, not the app's.
- There is **no App Group** — `bittr.entitlements` contains only `aps-environment`, the widget
  target has no entitlements file at all, and `application-groups` appears nowhere in the repo.
- Nothing in the extension ever *writes* `currency`.

So the lookup always returns `nil`, the CHF branch never runs, and a Swiss user with CHF selected
in the app still sees `€` and the euro price on their home screen. The same isolation means the
`mostrecentwidgetdata` cache the widget writes is invisible to the app and vice versa.

Fixing it on iOS needs an App Group shared between both targets. **For Android, use a shared
store from the start** (DataStore in a shared module, read by both the app and the Glance
provider) so the currency preference actually reaches the widget.

### 7.2 The widget ignores `EnvironmentConfig` — ~~open~~ **fixed on iOS since this was written**

> **Corrected 2026-09-13 (BIT-76).** This defect no longer exists in the source. The spec
> was written against `c297ed1`; on `ios-parity` the widget builds its URL from
> `BittrAPIEnvironment.baseURL` (`BittrWidget.swift:58`), a Foundation-only type compiled
> into **both** targets (`ios/BittrWidget/BittrAPIEnvironment.swift`), with a
> "Check hard-coded API URLs" build phase failing the build if a literal reappears. A
> Debug build now reads `https://staging.getbittr.com/api`.
>
> Consequence for BIT-76's capture: a Debug build is **not** a route to the `N/A` state —
> staging serves `/price/btc` (verified HTTP 200 on 2026-09-13), so it shows a real price.
>
> The original text, kept because the Android guidance still stands:

The price URL is a hard-coded production string. Every other price call in the app goes through
`EnvironmentConfig.bittrAPIBaseURL`. Low impact — it is public price data — but a staging build's
widget silently reads production. Android should route the widget's fetch through the same config
the app uses.

### 7.3 A stale price is indistinguishable from a live one

The cache is used verbatim on fetch failure and the widget renders no timestamp or staleness
indicator, so a device that has been offline for a week shows a week-old price as though it were
current. This is a **product** question, not a porting one: the Android widget will reproduce the
behaviour unless someone decides otherwise. Worth a designer's opinion before Phase 4 item 11.

---

## 8. Out of scope for this document: the Live Activity

`BittrWidgetBundle` ships **two** widgets. Alongside `BittrWidget` it registers
`SwapLiveActivity` — the onchain→lightning swap Live Activity rendered in the Dynamic Island and
on the Lock Screen (`ios/BittrWidget/SwapLiveActivity.swift`, `SwapActivityAttributes.swift`).

It has the **same problem as the price widget and a worse version of it**: Maestro cannot drive
the Dynamic Island or the Lock Screen either, so it is equally absent from the BIT-3 catalog —
but unlike the price widget it has real state (five `SwapPhase` values, each with its own title,
subtitle, icon and tint), it is driven by remote pushes, and its Android equivalent is an ongoing
notification, which is a different construct rather than a direct port.

The BIT-3 audit that produced BIT-11 flagged only the price widget and missed this one. It needs
its own scoping decision and its own spec; this document deliberately does not cover it.

**Both now exist: [`swap-live-activity-spec.md`](swap-live-activity-spec.md) (BIT-75).** It reached
the same decision as §1 here — in scope for the port, out of the v1 Maestro gate — but two of the
premises above turned out to be wrong, and anyone reading this section should not carry them
forward. The Android counterpart is **not** "an ongoing notification, which is a different
construct": Android 16 ships Live Updates (`NotificationCompat.ProgressStyle` + promoted ongoing),
which is a real counterpart, and the status-bar chip is the counterpart to the Dynamic Island's
compact presentation. And it is not a hand-checked surface — unlike this widget, most of it is
assertable in a JVM unit test. See that document's §1 and §7.
