# Android parity — the critical path

The fastest route from what the Android app is today to an app with the same
features as iOS. Written 2026-09-12 against `android-parity` (`d4acd07`), the
iOS tree at the same commit, and the live Maven Central metadata.

Parity is defined by `shared/flows/`: **36 top-level Maestro flows** (29 under
`features/`, 7 under `onboarding/`) plus 6 helper subflows. iOS passes them.
`shared/docs/parity.md` is the per-flow tracker; this file is the ordering.

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
| `features/bitcoin_value` | ValueVC | price API, no wallet state |
| `features/bitcoin_map` | MapVC | BTCMap public API; SDK settled in BIT-53 (coarse-location constraint is binding) |
| `features/academy` | Academy | content API |

Also in this wave, not flow-bearing on their own: the Home shell in its
no-funds state, Settings and Device details as screens, and wiring BIT-72's
scanner result into a destination parser (`AddressParsing.swift:15` is the iOS
single entry point for scan and paste — port it once, Send consumes it later).

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

Ranked by how much each unblocks. Only the founder can clear items 1–5.

1. **BIT-6 is marked `blocked` with an empty unblock descriptor, and the
   Bitcoin Wallet Engineer is `idle`, not paused.** The long pole — 26 of 36
   flows — has no recorded blocker and an available owner. This is the single
   highest-leverage item on the board and it costs one status change.
2. **The Backend & API Engineer is paused** (since 2026-09-11T14:45Z). Gates
   Wave 3's two server changes. Unpausing now buys the lead time to land them
   before the client needs them.
3. **Backend repo credential** — a deploy key, org PAT or App install that can
   reach the backend repo. The existing key is scoped to `bittr-ios-app` only.
4. **Self-hosted Android CI runner.** Not on the build path, but it is the
   *gate* — "parity" means these flows pass in CI. Must be x86_64 (see above).
5. **Firebase project** — push flows only, Wave 3.
6. **A trunk agents can push to.** `origin/android` is still at `c297ed1` and
   does not contain the BIT-93 arc; `android-parity` is 37 commits ahead. The
   instance-wide pre-push hook refuses `master`/`develop`/`android`, so every
   wave queues behind a manual merge unless `android-parity` is blessed as the
   landing branch. It already works that way in practice.
7. **The Mobile Product Designer is paused**, leaving two design defects in
   review (BIT-94's invisible dark-mode buttons; the consent Switch track at
   1.65:1). Cheap to clear, and they compound as screens multiply.

## What this file is not

It is not a re-plan of BIT-6, whose deliverables stand as written, and it does
not re-open BIT-8/BIT-20 storage decisions or BIT-53's map SDK choice. It
orders work that is already specified.
