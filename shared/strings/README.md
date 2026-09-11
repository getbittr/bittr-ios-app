# Strings

Canonical i18n source for both apps. One JSON file per locale (`en.json`, `nl.json`, …). A generator script produces `Localizable.xcstrings` for iOS and `strings.xml` for Android.

Plurals and gender variations use ICU MessageFormat (understood by both platforms).

## Migration plan

The iOS app currently has strings in scattered `*Language.swift` files. Phase 0 walks each screen for Maestro flows; while there, the strings get migrated into the canonical JSON.

## Generator

To be added (`build.{js,py,sh}`). Runs in CI before each platform build, and on demand during dev. Generated platform files are committed for diff visibility.

Until it exists, `en.json` holds only keys that had to be agreed across both platforms ahead of the migration. The iOS copy in `ios/bittr/Language.swift` is still what ships on iOS; keep the two identical by hand for those keys. Markup in the JSON is the iOS convention (`<b>`, `<br>`) — the generator is responsible for mapping `<br>` to `\n` for `strings.xml`.

## Strings that are privacy or regulatory representations

Some strings are not marketing copy — they are statements about what the app does with user data, and a wrong one is a compliance problem rather than a typo. These carry a review trail and must not be reworded without repeating it (Compliance read + a factual check against the code):

| Key | Reviewed under | Represents |
|---|---|---|
| `mapvcpoweredbyalert` | BIT-56 (from BIT-45) | That the places lookup sends the user's location nowhere, and that whoever serves the map tiles sees the on-screen area |

**Review trail for `mapvcpoweredbyalert`** — both reads are complete against the wording at `d610cac`, which is the wording that ships:

- **Factual check against the code** — BIT-70, Application Security Engineer, 2026-09-11. Cleared.
- **Compliance read** — BIT-69, Compliance & Regulatory Officer, 2026-09-11. **ADVISORY (approved to ship as written)** under §7 of the `perimeter` document on BIT-27.

Two standing conditions came out of the compliance read. They constrain future edits to this string, not the current text:

- **Do not add a "see our privacy policy" pointer to this alert until BIT-71 lands.** The policy names no map processor and mentions location, maps and tiles nowhere, so a cross-reference would point at a disclosure that does not exist. The alert is accurate standing alone, which is why it is approved standing alone.
- **Do not strengthen the BTCMap clause.** `getBitcoinMapURL` carries no coordinate, but it is a direct device→`api.btcmap.org` call, so BTCMap receives the device IP on every sync like any HTTPS host. "Your location is never sent" is true because *your location* here means the permission-derived fix, which the next sentence makes explicit. Anything of the form "BTCMap learns nothing about you" would be false.

The `mapvcpoweredbyalert` claim depends on a specific engineering property: the client downloads the **whole** BTCMap dataset and filters by proximity on-device (`getBitcoinMapURL` sends no lat/lon or bbox). If the Android port ever fetches places by bounding box — cheaper, and the obvious thing to reach for — the claim becomes false on Android. Treat the whole-dataset sync as load-bearing, not as an implementation detail.

The string deliberately says **"whoever serves them"** rather than naming a tile host, and it deliberately scopes the strong claim to the *places lookup* rather than to the app as a whole. Both are load-bearing:

- iOS renders with MapKit (`MKMapView`, `ios/bittr/Map/MapViewController.swift:18`, with no `MKTileOverlay` or other tile override anywhere in `ios/`), so Apple's tile servers see the viewport today. Android is decided for MapLibre on tiles bittr serves (BIT-53, `android/docs/map-sdk-decision.md` at [`cab42de`](https://github.com/getbittr/bittr-ios-app/commit/cab42de) — that path is on the BIT-53 branch and only resolves here once both merge), which has no third party at all. One sentence has to be true in both worlds, so it names neither.
- The strong claim is attached to the places lookup because that is where it is unconditionally true, on every platform and in every tile configuration: `getBitcoinMapURL` carries no coordinate, it is the only BTCMap URL in the repo, and CoreLocation is confined to `ios/bittr/Map/` — no code path sends a fix to bittr's backend at all.

**What pins the tile paragraph is iOS being MapKit, not an argument that self-hosting always discloses.** That distinction matters, because the second claim is false for half of BIT-73's option space and would wrongly read as "no upgrade is ever possible":

- Tiles from a host bittr controls (PMTiles on a CDN) — viewport plus IP on every pan, so the disclosure moves inside bittr rather than disappearing.
- A basemap shipped in-app (`MBTilesFileSource` over a fixed-region MBTiles) — no tile request leaves the device, so bittr genuinely does not learn the area.

BIT-53 names both as live options for BIT-73 and has not chosen between them. So the upgrade trigger is **both platforms off third-party tile servers with an on-device basemap**, at which point the tile paragraph can be deleted rather than softened. Until then it stays, because for as long as iOS renders with MapKit the shared string has to concede a recipient whatever Android does. Naming bittr as the tile host is separately gated on the BIT-73 pipeline actually shipping, and must not land before it.

### The tile-log answer changes what this string may say (BIT-73 DoD 5)

If BIT-73 lands as a **hosted** basemap rather than an in-app one, bittr's own tile server receives viewport plus IP on every pan. BIT-73 DoD 5 requires that request logging be decided deliberately — off, IPs truncated at the edge, or a stated retention window — and the Android Lead will report which. That answer is a copy input, so record it here when it arrives rather than treating it as an ops detail:

| If the answer is | What this string may then say |
|---|---|
| Logging off, or IPs truncated before they are stored | The tile paragraph may say bittr does not learn who looked where, once the pipeline ships. It still may not say *nothing* leaves the phone — the request does. |
| A stated retention window | The paragraph stays as-is. A window is a limit on keeping, not on receiving, and this string is about what is received. |
| Undecided | The paragraph stays as-is. "Whoever serves them" is true regardless, which is why it was written that way. |

None of these unblock anything: while iOS renders with MapKit, Apple is a recipient whatever Android's logging policy is, and a shared string cannot claim otherwise.

### This string does not gate the tile host, and must not be read as doing so

The BIT-53 doc and BIT-73 both record a constraint that no map screen may point at a vendor's tile host, and both attribute it to the copy — true while the *shipping* string is the old unqualified "we don't share your location with third parties". Once this rewrite ships, that attribution lapses: "whoever serves them sees the area you are looking at" is equally true of MapTiler, so the copy stops forbidding a vendor host.

The constraint should survive on its own footing — Ruben chose self-hosted tiles on 2026-09-11 (BIT-53) — and not on this sentence. Do not read the merge of this rewrite as authorisation to point the map at a vendor.

### This alert is not a notice, and must never be recorded as one

The alert is opt-in behind a small attribution credit — it appears only when the user taps "Powered by BTCMap.org" (`poweredByTapped`, `ios/bittr/Map/MapViewController.swift:103`). Most users who open the map will never see it.

That makes it good practice, not disclosure. Do not cite this string — in a data-safety form, a DPIA, a privacy-policy review, or a regulator answer — as evidence that the tile recipient has been disclosed to users. That burden sits entirely on the privacy policy and the two store data-safety declarations, which is BIT-71 and is not done. Flagged by the Compliance & Regulatory Officer on BIT-69, recorded here because the merge of this rewrite is exactly the moment someone would be tempted to tick that box.

### The string has a length budget, and the copy is not what gives way

The alert card has no scroll view. The message is one `UILabel` with `numberOfLines = 0` (`ios/bittr/AlertManager.swift:291–294`) inside a card capped at `heightAnchor ≤ host.view.bounds.height` (`:129`). The cap is a required constraint and the label's content height is not, so on a screen too short for the text the label compresses and the **last** paragraph is what disappears. On this string the last paragraph is the tile disclosure — the concession. Truncation here does not degrade the copy, it reverts it: what survives on screen is an unqualified "your location is never sent", which is the BIT-45 defect the rewrite exists to remove.

The rewrite roughly doubled the string (269 → 558 plain characters), so the check is real. It is being run on an iPhone SE 2/3 — 375×667pt, in scope at deployment target 17.4 — under **BIT-82**, and that render gates the merge.

Two independent calculations disagree on whether it fits, which is why one screenshot is worth more than a third calculation:

| | Result |
|---|---|
| Compliance (BIT-69) | a few percent over on SE, stated as inside their error bars |
| Growth & Content (BIT-56) | ~430pt of text against a ~526pt budget — fits, with about four lines of slack |

The budget: label width 275pt (card inset 10 each side, label inset 40 each side, `:328–329`); 16px at `line-height: 1.28` → 20.5pt per line (`ios/bittr/Extensions/String.swift:187–189`); chrome above and below the label 141pt (19 + 17 icon + 25 + 25 + 40 button + 15, `:157–160`, `:192`, `:327–334`); cap 667pt. Greedy wrap puts the message at 21 lines. It only overflows if the average glyph advance at 16px Gilroy-Regular is ≥ ~9.8pt, which would be wide for mixed English text. Both figures are arithmetic — neither was rendered.

**If it does not fit, the fix is the container, not the copy.** Wrap the message in a `UIScrollView`, or lower the priority of the height cap. Shortening the message is not available as a remedy: every paragraph is load-bearing (see the two standing conditions above), the shortest thing to cut is the tile disclosure, and any reword re-triggers both reads. A container fix needs neither.

The Maestro flow does not cover this. `alert.button.0` is pinned to the card and stays visible while the label is what compresses, so the flow passes on a truncated alert.
