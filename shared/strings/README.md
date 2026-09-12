# Strings

Canonical i18n source for both apps. One JSON file per locale (`en.json`, `nl.json`, …). A generator script produces `Localizable.xcstrings` for iOS and `strings.xml` for Android.

Plurals and gender variations use ICU MessageFormat (understood by both platforms).

## Migration plan

The iOS app's copy lives in **one** table: `allWords` in `ios/bittr/Language.swift`, 572 keys. The other ten `*Language.swift` files hold no copy at all — they are `setWords()` / `changeColors()` extensions that call `Language.getWord(withID:)`, so they are consumers, not sources. Phase 0 walks each screen for Maestro flows; while there, the strings get migrated into the canonical JSON.

What *is* scattered is the copy that never made it into `allWords` — see "Copy outside the table" below. That is the part a migration of `allWords` alone will walk past.

### The consolidation is verbatim

**Moving copy is in scope. Rewording it in the same change is not.** If a string has to change, change it in a separate commit, so that when a flow goes red the cause is obvious.

This is not a style preference, though it is now a much smaller exposure than it was. The suite used to identify alerts by their **copy**, because copy was the only thing available to identify them by: `alert.button._index` and `alert.textField` were the only accessibility ids on the alert surface. BIT-78 gave each alert an id of its own (`alert.lowFee`, `loading.syncingWallet`, …), so 26 of those matchers became id selectors and their lock entries went away. What is left:

- **78** `text:` matchers, **45** of them distinct, across **19** flow files
- **14** of those 45 are app copy: they depend on **11** keys in `allWords` and **6** hardcoded literals (one of the 14, `Unavailable`, is pre-locked for a flow still in review)

None of the remaining 14 is on the alert surface. They are screen labels (`send.toLabel`, `send.availableLabel`, `swapStatus`), the keyboard accessory's **Done**, and OS-owned UI — text is the right selector for those, or the only one.

Maestro matches `text:` as a case-insensitive regex against an element's **entire** text, which is why the suite wraps partial matchers in `.*` and writes the rest bare. The guard matches the same way. That is not a detail: under a substring rule, rewording `cancel` from "Cancel" to "Cancel payment" looks unchanged, while Maestro's `text: "Cancel"` stops selecting the button. A guard more permissive than the tool it guards goes quiet on exactly the rewording it exists to catch.

A word changed in transit breaks those assertions **silently** — a copy change isn't a behaviour change, so nobody expects a test result from it — and, once both apps read this directory, **on both platforms at once**. The failure then looks like an Android port bug, weeks later.

### The guard

`check_flow_copy.py` pins every text the suite matches on to the copy it depends on, and re-resolves that lock against every source present — `ios/bittr/Language.swift` and `shared/strings/en.json`, overlaid in that order, so a key that has moved resolves from its new home and the rest from the old one. Same lock, both sides of the migration commit **and every point in between**:

```sh
./shared/strings/check_flow_copy.py                             # before: green
# … move a key, or all of them …
./shared/strings/check_flow_copy.py                             # after: green == verbatim
./shared/strings/check_flow_copy.py --source ios/bittr/Language.swift   # pin the source explicitly
./shared/strings/check_flow_copy.py --update                    # re-lock after a deliberate copy change
./shared/strings/test_check_flow_copy.py                        # prove the guard still bites
```

The overlay is load-bearing in both directions. Reading only `en.json` once it exists reads a half-migrated tree as a mass deletion — BIT-56 landed a two-key `en.json` on `ios-parity` and the guard reported 10 keys missing that had never moved. Reading only `Language.swift` would let the Swift table's leftover copy of a moved key mask a rewording in `en.json`. `en.json` wins, because that is where the key is going; both readings are covered by a test.

It runs in CI (the `build` job in `.github/workflows/android-maestro.yml`, alongside the test-id checks) on any change to `shared/flows/`, `shared/strings/` or `ios/bittr/Language.swift`. Failures name the flow that would have gone red, so the cost of finding out is a CI minute rather than a simulator run.

`copy-lock.json` classifies each matcher. Only `copy` is enforced; the rest carry a `why`, so an exemption is a decision on the record rather than an oversight:

| class | meaning |
| --- | --- |
| `copy` | app copy — must still exist, verbatim, as the declared keys and literals |
| `system` | OS-owned UI: the iOS permission alerts, the paste prompt, the share sheet |
| `data` | regtest addresses, invoices, amounts, currency codes, `${output.*}` captures |
| `payload` | text the flow itself supplies (a push payload it posts, a note it types) |
| `review` | proposed by `--update`, undecided — **fails the check**, it is not a resting state |

A new `text:` matcher in a flow fails as `undeclared` until someone classifies it. That is deliberate: the alternative is a matcher that silently depends on copy nobody knows about.

The guard does not replace re-running the flows. It removes the *silent* failure mode; a real run is still what proves behaviour. Re-run all 38 iOS flows immediately after the move, before any Android work depends on it — iOS is the control, and `suite.yaml` covers only 25 of the 38, so the rest need their per-flow commands from the BIT-3 reference set.

### Copy outside the table

Six strings the suite asserts on are **not** in `allWords`, so a search-and-move of that table will not find them. They are locked as `literals` — text that must still appear, quoted, in a named file:

| copy | where it lives | the flow that depends on it |
| --- | --- | --- |
| `Copy` | `ReceiveViewController.swift` — `UIAction(title:)` on the QR long-press menu | `receive_onchain.yaml` |
| `Share` | `ReceiveViewController.swift` — the other `UIAction` on that menu | `receive_onchain.yaml` |
| ` sats` | `MoveViewController.swift` — `"\(instantSatoshis)".addSpaces() + " sats"` | `remove_wallet.yaml` |
| `Swap complete` | `SwapLiveActivity.swift` **and** `SwapLiveActivityController.swift` — a third copy of the `swapstatusswapcomplete` key | `swap.yaml`, `send_swap_suggestion_onchain.yaml` |
| `You can send 0 satoshis.` | `Main.storyboard` — the label's design-time text, which is what a flow sees before the first render | `send_onchain.yaml` |

`Swap complete` is the same sentence stored three times (the `swapstatusswapcomplete` key plus both live-activity files). Collapsing it into one key is the right end state and the consolidation is the moment to do it — but as a deliberate commit: all three copies are locked, so a silent dedup goes red rather than quiet.

`Syncing wallet` had the same three-way split (`syncingwallet`, `syncingwallet3`, and a hardcoded copy in `ResetApp.swift`) and used to be locked for the same reason. It no longer is: the two flows that depended on the wording now select `loading.syncingWallet`, so the guard has nothing left to protect there. The duplication is still worth collapsing — it is just no longer a way to break the suite.

### Longer term

~~Give the alert surface real per-alert accessibility ids, so assertions stop depending on wording at all.~~ Done in BIT-78 — see `shared/test-ids/README.md`, "Alerts". The remaining `copy`-class entries are the ones that genuinely assert wording on a non-alert surface.

## Generator

To be added (`build.{js,py,sh}`). Runs in CI before each platform build, and on demand during dev. Generated platform files are committed for diff visibility.

Until it exists, `en.json` holds only keys that had to be agreed across both platforms ahead of the migration. The iOS copy in `ios/bittr/Language.swift` is still what ships on iOS; keep the two identical by hand for those keys. Markup in the JSON is the iOS convention (`<b>`, `<br>`) — the generator is responsible for mapping `<br>` to `\n` for `strings.xml`.

`check_flow_copy.py` reads `en.json` flat or nested (dotted keys), and ignores keys starting with `_`, so a metadata header in the locale file is fine.

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

The rewrite roughly doubled the string (269 → 558 plain characters), so the check was real. It was run on an iPhone SE 2/3 — 375×667pt, the smallest device in scope — under **BIT-82**, and it gated the merge.

**Resolved: it fits, with about five lines of slack. The hold is released.** Three calculations were made; the third one measured the part the first two had guessed.

| | Result |
|---|---|
| Compliance (BIT-69) | a few percent over on SE, stated as inside their error bars |
| Growth & Content (BIT-56) | ~430pt of text against a ~526pt budget — fits, about four lines of slack |
| Application Security (BIT-82) | **message 421.8pt, card 562.8pt against a 667pt cap — fits, ~104pt spare** |

The budget the first two worked from: label width 275pt (card inset 10 each side, label inset 40 each side, `:328–329`); 16px at `line-height: 1.28` → 20.5pt per line (`ios/bittr/Extensions/String.swift:187–189`); chrome above and below the label 141pt (19 + 17 icon + 25 + 25 + 40 button + 15, `:157–160`, `:192`, `:327–334`); cap 667pt.

What made the third figure different is that it did not guess glyph widths. It parsed the real `Gilroy-Regular.ttf` / `Gilroy-Bold.ttf` advances and GPOS kerning and calibrated the line-breaker against the one real iOS render of this alert we have (`03a_powered_by.png`, decoded pixel by pixel), which surfaced a genuine correction: **iOS renders the bold run ~5% wider than Gilroy-Bold's own metrics.** That matters here because the label is built by the HTML importer (`String.swift:184–189`), so a browser engine fed the same markup is a faithful oracle for everything *except* that discrepancy. With it applied the model reproduces the reference capture to within 0.6pt per line. The two models agree on geometry exactly — 421.8pt of message plus the 141pt of chrome above is 562.8pt of card — so the only thing that was ever in dispute was the advances, and that is now measured rather than assumed.

It is still not a simulator capture; nobody on this board has a Mac. Two facts close the two ways the cap could nonetheless bind, and both are checkable from the project rather than from a render:

- **No supported device is narrower or shorter than 375×667.** The sensitivity analysis flips at a device narrower than ~320pt. There is none: the app target `com.bittr.bittr` sets `IPHONEOS_DEPLOYMENT_TARGET = 17.4` (`ios/bittr.xcodeproj/project.pbxproj`), and iOS 17 drops every 320pt device — the iPhone SE 1st gen stops at iOS 15. The SE 2/3 measured here *is* the floor.
- **The text cannot grow under the user's control.** Overflow would also follow from Dynamic Type inflating the label, but this alert does not participate in it: the message is rendered from HTML with a hard-coded `font-size: 16px` (`String.swift:187–189`), and `adjustsFontForContentSizeCategory` and `UIFontMetrics` appear nowhere in `ios/`. Accessibility text settings do not change this label's height.

Even subtracting both a 34pt home-indicator inset and the 20pt status bar, the card still clears by ~50pt. Releasing the hold on that basis.

**This re-opens if any of three things change**, and the check is cheap enough to redo: a paragraph is added to the string, the deployment target drops below iOS 17, or the app adopts Dynamic Type for alert text.

**If it ever does not fit, the fix is the container, not the copy.** Wrap the message in a `UIScrollView`, or lower the priority of the height cap. Shortening the message is not available as a remedy: every paragraph is load-bearing (see the two standing conditions above), the shortest thing to cut is the tile disclosure, and any reword re-triggers both reads. A container fix needs neither.

The Maestro flow does not cover this. `alert.button.0` is pinned to the card and stays visible while the label is what compresses, so the flow passes on a truncated alert.
