# Android parity — the critical path

The fastest route from what the Android app is today to an app with the same
features as iOS. Written 2026-09-12 against `android-parity` (`d4acd07`), the
iOS tree at the same commit, and the live Maven Central metadata.

Parity is defined by `shared/flows/`: **36 top-level Maestro flows** (29 under
`features/`, 7 under `onboarding/`) plus 6 helper subflows. iOS passes them.
`shared/docs/parity.md` is the per-flow tracker; this file is the ordering.

## Trunk: `android-parity` — decided, not a convention

**Ruben blessed `android-parity` as the landing branch on 2026-09-12** (BIT-93,
card `ddd39df5`, option *"android-parity is the trunk — land everything there"*).
Stack all port work here. He merges `android-parity` into `android` when he
wants a checkpoint — **per wave, not per branch**.

Practically, for anyone porting:

- Branch off `origin/android-parity`, merge back into it, push. No founder in
  the loop, no protected-branch wall.
- The instance-wide `pre-push` hook still refuses `master`/`develop`/`android`,
  and that stays. Do not try to route around it.
- `origin/android` is still at `c297ed1` and does **not** contain the BIT-93
  arc. That is expected now, not a defect to chase. `android-parity` is a
  strict descendant, so the eventual merge stays a fast-forward.

## Where the app actually is

| | iOS | Android |
|---|---|---|
| User-facing screens (`shared/docs/screens.md`) | 40 | 9 |
| Top-level Maestro flows passing | 36 | 0 (1 arc built, not yet driven) |
| Wallet engine | ldk-node 0.7.0 + bdk-swift 1.2.0 | none — `StubWalletService` returns `Uninitialized` |

The 9 Android screens are the create-wallet arc from BIT-93 (start, create,
mnemonic, verify, PIN, confirm, ready) plus the unlock screen and a home
placeholder. The seed is real and Keystore-wrapped; there is no node behind it.

## The one fact that sets the order

**The wallet engine gates about 26 of the 36 flows.** Every flow that shows a
balance, an address, an invoice, a transaction or a channel is downstream of it.
Ten flows are not, and can be built and driven against the seed layer that
already exists.

So the schedule is not "port screens in screenshot order". It is: **start the
engine now, and run the engine-independent screens in parallel beside it.**

## The engine is de-risked — this was the big unknown

BIT-6 calls the wallet layer "the highest-risk work in this port". The specific
risk that dependencies wouldn't line up is now closed. Verified against
`repo1.maven.org` today, not inferred from a release page:

| iOS pin (`Package.resolved`) | Android artifact | Status |
|---|---|---|
| `ldk-node` 0.7.0 | `org.lightningdevkit:ldk-node-android:0.7.0` | **exists** — 26 MB AAR, published 2025-12-03 |
| `bdk-swift` 1.2.0 | `org.bitcoindevkit:bdk-android:1.2.0` | **exists** |

Exact version parity with what iOS ships, so the two platforms can be held to
the same protocol behaviour rather than reconciled across a version gap. The
AAR's transitive deps are ordinary: JNA 5.12.0, slf4j-api 1.7.30,
kotlin-stdlib-jdk7, kotlinx-coroutines-core 1.6.4, appcompat, core-ktx.

Two consequences worth knowing before the work starts, both from the AAR itself:

- **Native libs ship for `arm64-v8a` (26 MB), `armeabi-v7a` (18.6 MB) and
  `x86_64` (24.8 MB)** — ~70 MB uncompressed. A universal debug APK will jump
  from today's 12.7 MB to roughly 40 MB. Real devices get one ABI via an app
  bundle, so the shipped download is unaffected, but CI artefacts and the
  hand-installed debug builds will be large. Use ABI splits for the debug APK.
- **`x86_64` is present, `x86` is not.** The CI emulator must be x86_64. That
  is the normal choice anyway, but it is now a hard constraint rather than a
  preference.

## Waves

Waves 1 and 2 run **concurrently** — different owners, no shared dependency.
That parallelism is where the time is won.

### Wave 1 — no engine, no backend, no credential (can start today)

Ten flows and the whole navigational skeleton. Every item is buildable against
the seed/PIN layer that BIT-93 already landed.

| Flow | iOS source | Note |
|---|---|---|
| `onboarding/smoke` | Signup1 | test-ID pipeline end to end |
| `onboarding/happy_path_wallet` | Signup1–7 | **screens built** (BIT-93); needs the flow driven |
| `onboarding/restore_wallet` | RestoreVC | **screens built** (BIT-96); needs the flow driven |
| `onboarding/fresh_install_unhappy` | Signup1–7 | the validation gates; BIT-19's wrong-word rejection |
| `features/pin_warning` | PinVC | **screens built** (BIT-97); needs the flow driven |
| `features/wrong_pin` | PinVC | **screens built** (BIT-97); no-channel branch only — the channel close is Wave 2 |
| `features/forgot_pin` | PinVC → RestoreVC | **screens built** (BIT-97); needs the flow driven |
| `features/bitcoin_value` | ValueVC | **screens built** (BIT-99); needs the flow driven |
| `features/bitcoin_map` | MapVC | **screens built** (BIT-99); needs the flow driven. Basemap tiles wait on BIT-73 — see below |
| `features/academy` | Academy | **screens built** (BIT-99); needs the flow driven |

Also in this wave, not flow-bearing on their own: the Home shell in its
no-funds state, Settings and Device details as screens (**built** — BIT-98),
and wiring BIT-72's scanner result into a destination parser
(`AddressParsing.swift:15` is the iOS single entry point for scan and paste —
port it once, Send consumes it later).

`features/settings` appears in neither wave's table on purpose. Its screens are
Wave 1 and are built, but the flow itself asserts a synced wallet in three
places — the header spinner stopping, a `CHF` conversion on Home, and the
two-button Copy/Close alert on the Public-key row — so it goes green in Wave 2
behind BIT-6. `SettingsFlowTest` walks everything either side of those three
steps on the JVM, and names them.

**The three read-only screens landed on 2026-09-12 (BIT-99)** as `:feature:value`,
`:feature:map` and `:feature:academy`, all three reachable from Home through the
identifiers their flows tap (`home.currencyButton`, `home.mapButton`,
`nav.academyButton`). BIT-98 replaced the Home placeholder those first hung off
with the real no-funds Home, which carries the same three identifiers;
`Wave1ReachabilityTest` is what holds that swap honest. Three things about them
are worth knowing
before the flows are driven on an emulator:

- **The map draws no basemap yet, deliberately.** `MapBasemap.STYLE_URI` is null
  and the renderer paints a background-only style, because
  `android/docs/map-sdk-decision.md` says no map screen may point at a vendor's
  tiles while the current copy ships, and the pipeline that would serve bittr's own
  is BIT-73. Everything `bitcoin_map.yaml` drives is the app's own code over its
  own data and works today; only the drawn streets are missing. One constant
  changes when BIT-73 lands.
- **The Academy content is transcribed, not retyped.** `tools/academy_content.py`
  generates `AcademyContent.kt` from the iOS demo data — four levels, 22 lessons,
  360 components. Lesson ids are the completion keys on both platforms, so they
  have to match exactly. Re-run the script rather than editing the output.
- **The price and BTCMap requests go to the live APIs.** Neither needs a wallet, a
  node or a credential, which is why these were Wave 1 — but the value flow's
  90-second wait is real, and it is two sequential round trips.

~~wiring BIT-72's scanner result into a destination parser~~ — **done (BIT-100,
2026-09-12).** `core/common/…/destination/` holds a pure-Kotlin port of
`AddressParsing.swift:15`: bare address, BIP-21 with an amount, BOLT-11, LNURL,
across bech32/bech32m and base58check, with the network taken from
`BuildConfig.BITCOIN_NETWORK` (debug = regtest, as on iOS). 30 unit tests, no
node and no emulator.

Two things landed with it that are worth knowing about:

- **BIT-72's scanner was merged at the same time.** It had been `done` since it
  was built but sat on `feature/bit-72-scanner-screen` with no branch
  containing it, so `:feature:scanner` was not in the trunk build at all.
- **The iOS LNURL-auth case bug (BIT-84/BIT-85) is not ported.** Detection
  lower-cases; routing then matches `tag=login&k1` case-sensitively, so an
  upper-cased query misroutes. The port matches case-insensitively throughout
  and pins it with a test.

Send consumes the parser when it is built on BIT-6's wave; until then the
scanner route returns a parsed `Destination` on the caller's back stack entry,
and `ScannerRouteWiringTest` fails the build if that regresses to a bare pop.

### Wave 2 — the engine (BIT-6), the critical path

`ldk-node-android` 0.7.0 + `bdk-android` 1.2.0 behind the `WalletService` seam
that BIT-93 widened. Then Receive, Send, Swap, transactions, balances, profits,
the sync overlay, and the channel-close branches of the wipe flows — about 15
flows directly, and it is a precondition for most of Wave 3 too.

Storage is already decided and is not open: BIT-8 rules 1–5 and BIT-20 rules
6–10, non-auth-bound Keystore AES/GCM, spec in `seed-storage-security` rev 3.

**This wave is the schedule.** Nothing shortens the port more than starting it
earlier. See "What's actually holding this up" below.

### Wave 3 — the bittr account, buying, push

`happy_path_signup`, `fresh_install`, `buy_signup`,
`buy_signup_no_notifications`, `buy_incoming`, `buy_more`, `payment_mode`, and
the three notification flows.

An important distinction that has been costing us: **the client port does not
need the backend repository.** It needs the API to exist, which it does
(staging/regtest). The repo is needed only for the two *server-side* changes —
accepting `android_device_token` and persisting
`exclusive_initiative_confirmed_at` — which are BIT-9's, not the app's. Those
two can be written the moment the credential lands; they do not gate the
client screens.

Push additionally needs Firebase, which only Ruben can provision.

### Wave 4 — release

Play Console, listing, store screenshots, the compliance arc. Genuinely later;
none of it shortens the path to a feature-complete app.

## What's actually holding this up

Ranked by how much each unblocks. Updated 2026-09-12 after Ruben answered the
two open calls on BIT-93 — four of the seven items below are now closed.

1. **BIT-6 is blocked behind two in-progress verification tasks** — BIT-59
   (wallet-layer instrumented tests in CI) and BIT-18 (Test K1, proving a
   non-auth-bound Keystore key survives lock-screen mutation). Both have active
   owners and are `in_progress`, so the long pole is *sequenced*, not stalled,
   and nobody outside those two issues can shorten it today.

   **Corrected 2026-09-12:** an earlier revision of this file said BIT-6 was
   "blocked with an empty unblock descriptor" and that clearing it "costs one
   status change". That is no longer true — `diagnostics/blockers` now reports
   two real first-class blockers. Do not act on the old reading.
2. **Backend repo credential** — a deploy key, org PAT or App install that can
   reach the backend repo. The existing key is scoped to `bittr-ios-app` only.
   Gates only the two *server-side* Wave 3 changes, not the client port.
3. **Firebase project** — push flows only, Wave 3.

With the four items closed below, **nothing on the founder's desk is on Wave 1's
critical path.** Wave 1 is start-now work; Wave 2 is owner-driven.

### Closed since this file was written

- ~~**A trunk agents can push to.**~~ **Answered: `android-parity` is the
  trunk** (2026-09-12). See the Trunk section at the top. Wave 1 no longer
  queues behind a manual merge.
- ~~**The Mobile Product Designer is paused.**~~ **Unpaused 2026-09-12.** The
  two design defects have an owner again: BIT-94 (invisible dark-mode buttons,
  fix ready on `feature/bit-94-dark-primary`) and BIT-95 (consent Switch track
  at 1.65 : 1).
- ~~**The Backend & API Engineer is paused.**~~ **Ruben's call, 2026-09-12: they
  stay paused for now.** This is a decision, not an open ask — do not re-raise
  it. Plan Wave 3's two server changes as blocked; the *client* half of Wave 3
  is unaffected, because it needs the API to exist, not the repo.
- ~~**Self-hosted Android CI runner.**~~ **Never was a blocker.**
  `android-maestro.yml:253` is
  `runs-on: ${{ fromJSON(vars.ANDROID_EMULATOR_RUNNER || '["ubuntu-latest"]') }}`
  — the self-hosted runner is an *unset optional override*. The emulator job
  runs green on GitHub-hosted `ubuntu-latest` today (run #71 on
  `android-parity`: KVM enabled, hardware-acceleration preflight passed,
  Maestro smoke green in 86 s). The x86_64 constraint above still holds; it is
  satisfied by the hosted image. Do not ask the founder for a runner.

## What this file is not

It is not a re-plan of BIT-6, whose deliverables stand as written, and it does
not re-open BIT-8/BIT-20 storage decisions or BIT-53's map SDK choice. It
orders work that is already specified.
