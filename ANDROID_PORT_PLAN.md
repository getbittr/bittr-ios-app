# Android Port Plan

Working plan for porting the iOS Bittr app to a first-class native Android app.
Decisions captured here so the plan survives across conversations.

## Goals & constraints

- **Feature parity at launch** — no MVP-by-subsetting.
- **Native, not cross-compiled** — Kotlin + Jetpack Compose + Material 3.
- **Two native apps in one repo** — so AI assistants can see both sides.
- **Solo dev** — One dev porting himself; the plan must be sustainable for one person.
- **Same backend** (`BittrService` at `EnvironmentConfig.bittrAPIBaseURL`) — no API changes.
- **No KMP** — explicitly chose two native codebases over a shared Kotlin core.
- **Maestro is the parity mechanism** going forward.

## Repo restructure (do first)

```
bittr/                          (rename repo from bittr-ios-app)
  ios/                          ← current root contents move here
  android/                      ← new
  shared/
    strings/                    ← canonical i18n source (consolidate *Language.swift)
    flows/                      ← Maestro flows — single source of truth, both platforms
    test-ids/                   ← shared accessibility ID constants (generated to both)
    assets/                     ← brand assets (icons, fonts already at root)
    docs/
      screens.md                ← screen inventory
      parity.md                 ← per-feature status tracker
```

The iOS app currently has ~10 `*Language.swift` files scattered across features. Phase 0
consolidates these into a single canonical i18n source, with `Localizable.strings` and
`strings.xml` generated from it.

## Strategy: Maestro-first Phase 0

**Insight:** instead of a manual screenshot pass to brief the designer, write Maestro
flows on the iOS app first and let them produce the screenshots automatically.

Why this is better than manual capture:

- The flows ARE the spec — writing them forces you to walk every screen, every state,
  every error branch. Same work as manual screenshots, but executable.
- Screenshots stay fresh — re-run the suite after any iOS change, get an updated
  catalog. Manual screenshots rot.
- Every state, not just happy path — empty / loading / error / synced / pending. The
  designer gets the full state matrix.
- Phase 0 and Phase 4 collapse — the flows that drove screenshots become the Android
  parity gate. Zero wasted effort.

Caveats baked into Phase 0:

- **Add `accessibilityIdentifier` on iOS as you write the flows.** Without test IDs from
  day 1, the flows won't port cleanly to Android and you'll redo the work.
- **Deterministic test environment required** — regtest + fixture data for sync, swaps,
  channel state, lightning balances. Pull this forward from Phase 1 PoC.
- **Maestro screenshots are device-res PNGs**, not design assets. They're reference
  material for the designer, not a substitute for a redesign.

## Phases

### Phase 0 status (in progress)

What's landed:

- Repo restructured into `ios/` + `android/` + `shared/` (this branch).
- Test-ID pipeline live: `shared/test-ids/test-ids.json` → `shared/test-ids/build.py` → `ios/bittr/Helpers/TestIDs.swift`. Maestro flows reference IDs via the hierarchical dot path.
- `UIView+AppTag.swift` extension added — receiving side for the `accessibilityIdentifier`-as-data migration. **Mechanical migration of the call sites in `shared/test-ids/README.md` is not yet done.**
- Maestro flows: `onboarding/{smoke,fresh_install,happy_path}.yaml`, `features/{buy_incoming,buy_more,receive,swap}.yaml`, `helpers/unlock.yaml`, plus four `runScript` helpers. Screenshot catalog lands in `shared/docs/screenshots/<flow>/<step>.png`.
- Regtest environment is **fully hosted** rather than the greenfield local stack originally planned (bittr backend at `staging.getbittr.com`, Esplora at `esplora.bittr.io`, Boltz at `boltz-api.bittr.io`, Electrum at `staging.getbittr.com:19001`, RGS via lightningdevkit). No local infrastructure required beyond the iOS simulator and the Node helper for push notifications. See `shared/docs/regtest.md`.
- `shared/docs/screens.md` and `shared/docs/parity.md` populated with the screens and features covered so far.

What's outstanding for Phase 0:

- Migrate the data-bearing `accessibilityIdentifier` usages to `appTag` (file list in `shared/test-ids/README.md`).
- Translation migration: `*Language.swift` → canonical JSON in `shared/strings/`. Not started.
- Flows for the rest of the screen inventory (Send, Restore, Settings, Map, Academy, Profits, Value chart, LNURL-Auth, Widget).
- Document administration of the hosted regtest infrastructure (`staging.getbittr.com`, `esplora.bittr.io`, the LN peer, `boltz-api.bittr.io`) so it's clear who owns what when it goes down.

### Phase 0 — Maestro flows + screenshot catalog (3–4 weeks)

- Restructure repo (`ios/`, `android/`, `shared/`).
- **Stand up new regtest environment** (greenfield — no existing regtest setup):
  - Local `bitcoind` in regtest mode + `electrs` for BDK indexing.
  - Local LDK Node peer for opening channels deterministically.
  - Boltz testnet for swap flows (regtest Boltz is harder to host; testnet is acceptable for fixture flows).
  - Mock `BittrService` via Maestro Mocks for backend-driven screens — no need to host a full backend instance.
  - Fixture script seeds wallets in known states (empty / synced / pending tx / open channel / settled swap / IBAN registered).
  - Document setup in `shared/docs/regtest.md` so it's reproducible on the Android side too.
- Write Maestro flow per screen: cover happy path + key state variants.
- Wire `takeScreenshot` into flows — output goes to `shared/docs/screenshots/<flow>/<state>.png`.
- Add `accessibilityIdentifier` to every interactive iOS element as flows are written.
  Source IDs from `shared/test-ids/` constants file.
- Migrate existing `*Language.swift` strings into canonical JSON in `shared/strings/` while walking screens.
- Output: `shared/docs/screens.md` (auto-linked to screenshots) — the designer brief.

### Phase 1 — Native dependency PoC (2–3 weeks, parallel with Phase 2 design)

Throwaway Android project proving the stack works before scaffolding the real app:

- `bdk-android` 1.x — receive + send on regtest.
- `ldk-node-jvm` 0.7.x — start node, open channel, send + receive lightning.
- `boltz-android` — submarine + reverse swap on testnet. **Replaces** the custom
  `BoltzSwiftSDK`, the secp256k1 fork, Musig2Bitcoin, and most of `SwapManager.swift` /
  `WebSocketManager.swift`. Confirmed acceptable by Ruben — no need to port custom Swift impl.
- Sentry Android, FCM, BiometricPrompt, Android Keystore for seed encryption.
- ABI splits + APK size sanity check (LDK + BDK native libs are heavy).

Output: `versions.toml` with pinned library versions and a "yes this works" memo.
**If anything blocks here, surface before design lands so scope can adjust.**

### Phase 2 — Design (parallel with Phase 1, ~6 weeks expected)

- Designer takes `screens.md` + screenshot catalog as input.
- Material 3, Android conventions: system back, bottom nav, FAB where appropriate,
  edge-to-edge, dark mode mandatory, dynamic color optional.
- Brand assets stay shared (`shared/assets/`); type system and component library are
  Android-native.
- Hand-off in Figma with component spec.

### Phase 3 — Scaffold (1 week, after Phase 1 + 2 land)

- Kotlin 2.x + Jetpack Compose + Material 3.
- Min SDK 26 (Android 8.0) — full keystore/biometric, no legacy hacks.
- Architecture: feature modules, MVI or MVVM+Flow, Hilt, Coroutines.
- Persistence: Room (replaces `CacheManager`'s storage), DataStore (replaces `UserDefaults`).
- Network: Retrofit + OkHttp against existing `BittrService`.
- Background: WorkManager (replaces `BackgroundSync.swift`).
- Push: FCM. **Backend ticket: handle both APNs and FCM tokens.**
- Navigation: Compose Navigation, single-Activity.
- Maestro CI: smoke flow on Android emulator goes green before any feature work.

### Phase 4 — Port features (long phase, 5–8 months solo)

Order matters — each layer unblocks the next:

1. Plumbing: `EnvironmentConfig`, `BittrService` (Retrofit), `Log`, `Reachability`, error types.
2. Wallet creation/restoration, PIN, biometric unlock, seed in Keystore.
3. BDK manager → on-chain sync, address gen, send.
4. LDK Node manager → start/stop, channels, send/receive lightning, LNURL decode, LNURL-Auth (after iOS lands).
5. **`CacheManager`** — 1,195 LOC, biggest file. **Redesign around Room + Flow, don't port line-by-line.**
6. Send/Receive UI + URI/QR parsing (CameraX + ML Kit barcode).
7. Swaps via `boltz-android` (thin wrapper).
8. Buy + IBAN.
9. Notifications + payout flow.
10. Map (Google Maps Compose), Academy, Profits, Settings, Transaction history.
11. Glance widget (mirrors `BittrWidget`).

For each feature: build screen(s), wire managers, extend Maestro flow, mark green in `parity.md`.

### Phase 5 — Parity-going-forward (Maestro as the gate)

- One `shared/flows/` directory drives both iOS and Android with matching test IDs.
- **Pre-merge rule:** any iOS PR that changes user-visible behavior must update the relevant flow. The flow then fails on Android until ported. The failing flow IS the Android ticket.
- CI runs `maestro test shared/flows/` against both iOS simulator and Android emulator. Both must be green; Android can be on a "known divergence" allowlist for in-flight features.
- `shared/docs/parity.md` lists every feature and its flow status. CI keeps it honest.

This works specifically because Ruben is solo — no team coordination, the test suite enforces what would otherwise require process discipline.

## What `boltz-android` eliminates

By using upstream `boltz-android` instead of porting the custom Swift implementation:

- `BoltzSwiftSDK.swift` — not ported.
- `BoltzAPI.swift` — not ported (covered by SDK).
- `SwapManager.swift` (~700 LOC) — replaced by thin Kotlin wrapper.
- Custom `RubenWaterman/swift-secp256k1` fork (`import-signatures-and-nonces` branch, Musig2 plumbing for Boltz) — **not needed on Android**.
- `Musig2Bitcoin` import — not needed.
- `WebSocketManager.swift` (~229 LOC) for swap status — likely covered by SDK.

Total saved: ~1,500–2,000 LOC of the trickiest cryptographic code.

## Risk register

| Risk | Mitigation |
|---|---|
| LDK Node JVM behavior diverges from Swift in subtle ways (recovery, channel state) | Validate in Phase 1 PoC; share regtest fixtures across both platforms |
| `CacheManager` schema migration is messy | Treat it as a redesign, not a port; fresh Room schema, accept some divergence in cache representation as long as user-facing behavior matches |
| Push notification semantics differ (iOS background vs. FCM data messages) | Backend ticket: handle both token types; design payload to be platform-neutral |
| Maestro flows drift from app reality | CI gate + require flow update in any UI-touching PR |
| `boltz-android` behavior differs from custom Swift port | Run a parallel testnet comparison during Phase 1; document any differences in `parity.md` from day one |
| Solo-dev fatigue / scope creep | Feature-freeze iOS for the duration where possible, or explicitly track Android lag in `parity.md` |
| Some screens hard to reach deterministically (transient sync, swap status) | Build mock/fixture infra in Phase 0 — same infra reused for Phase 4 Maestro tests |

## Concrete first three steps

1. Restructure repo: move iOS into `ios/`, create `android/` and `shared/` skeletons. Push as a branch.
2. Stand up regtest + fixture environment for the iOS app (deterministic Maestro state).
3. Write the first Maestro flow on iOS (probably wallet creation — the entry point) with `accessibilityIdentifier`s sourced from `shared/test-ids/`. Verify screenshot capture into `shared/docs/screenshots/`.

## Decisions

Captured from follow-up Q&A so they don't get lost:

- **Test infrastructure**: greenfield. No existing Maestro/XCUITest scaffolding. Build to 2026 best practices (see Maestro setup below).
- **Designer**: hybrid AI + freelance Material 3 specialist. AI tools (Stitch by Google, Figma AI, v0, Magic Patterns) for rapid first-pass screen exploration; human contractor (Dribbble/Contra/Toptal) for the design system and critical flows. Lean heavily on Material 3's component library so the contractor focuses on flows and brand application, not reinventing buttons. Rough budget $5–15k for a 50–70 screen pass.
- **FCM ownership**: us, no prior FCM experience. See FCM Implementation Notes below.
- **Translation format**: **JSON as canonical**, generated to platform-native formats. iOS 17+ uses String Catalogs (`.xcstrings`, JSON under the hood); Android uses `strings.xml`. Plurals via ICU MessageFormat. Small generator script in `shared/strings/`. Skip YAML (less tooling) and ARB (Flutter-specific).

## Maestro setup (2026 best practices)

- **Maestro Studio** for recording flows interactively (saves hand-writing YAML).
- **Maestro Mocks** for stubbing network calls during flows — use this for screens that depend on `BittrService` responses, so flows don't require a live backend.
- **Maestro Cloud** for parallel device matrix runs, or **GitHub Actions** with iOS simulator + Android emulator for cheaper CI. Recommend GHA for the regular pipeline, Cloud for periodic real-device validation.
- **`runScript`** for setup/teardown — wallet seeding, regtest funding, channel opening before flow starts.
- **Test IDs** (`accessibilityIdentifier` on iOS, `Modifier.testTag` on Compose). AI/text selectors exist but flake on screens with similar copy. Source IDs from `shared/test-ids/` constants file, generate per-platform.
- **Flow naming convention**: `<feature>_<state>.yaml` (e.g. `wallet_create_happy.yaml`, `wallet_create_invalid_pin.yaml`).
- **Screenshot directory**: `shared/docs/screenshots/<flow_name>/<step>.png` — Maestro's `takeScreenshot` writes here.
- **CI gate**: both iOS and Android runs of `maestro test shared/flows/` must pass; Android allowlist for in-flight features tracked in `parity.md`.

## Design strategy

Pure AI design tools as of 2026 are good for screen ideation and component generation but don't reliably produce a coherent design system across 50–70 screens for a financial app. Trust matters in a Bitcoin wallet — visual polish and consistency directly affect user confidence. Recommended split:

- **AI tools (free / low-cost)**: rapid first-pass mockups for individual screens. Useful inputs:
  - **Stitch by Google** (formerly Galileo AI) — text-to-Figma, strongest at Material design language.
  - **Figma AI** — in-context generation inside Figma, good for variant expansion.
  - **v0 by Vercel** — primarily web but useful for component-level exploration.
  - **Magic Patterns / Visily** — wireframe-to-design conversions.
- **Human contractor**: own the design system (typography, color, spacing, component library), critical flows (onboarding, send/receive, swap), and brand application. Source via Dribbble, Contra, or Toptal. Brief them with the Maestro-generated screenshot catalog from Phase 0.
- **Material 3 baseline**: don't pay a designer to redesign buttons. Use M3 components as-is; designer time goes to flow logic, illustration, brand voice.

Budget estimate: $5–15k for a contractor doing the full design system + screen redesigns, depending on rate and brand complexity.

## FCM implementation notes

Greenfield — no prior FCM experience on the team. Key things that bite first-timers:

- **Use HTTP v1 API only.** The legacy `/fcm/send` API was killed mid-2024. Backend SDKs (Firebase Admin) handle this transparently; just make sure docs/examples are recent.
- **Setup**:
  1. Firebase project → add Android app → download `google-services.json` into `android/app/`.
  2. Backend: install Firebase Admin SDK, mount service account key from env var (never commit).
  3. Backend token registration endpoint takes `{ token, platform: "ios" | "android" }`. Store both alongside user.
- **Message types**: use **`data` messages**, not `notification` messages, for payment alerts. Reasons:
  - App controls how to display (custom UI for incoming Lightning payment).
  - Works the same in foreground and background.
  - Set `priority: "high"` and `androidConfig.priority: "HIGH"` so payments don't get throttled by Android battery saver.
- **Token rotation**: subclass `FirebaseMessagingService`, override `onNewToken`, re-register on backend. Tokens rotate on app reinstall, data clear, and occasional Google rotation.
- **APNs stays direct** — current iOS setup talks to APNs directly (not via Firebase). Don't migrate it; backend dual-sends (APNs for iOS tokens, FCM for Android tokens) based on the `platform` field. Firebase Admin SDK only handles the FCM path.
- **Background processing for incoming Lightning payments**: Android 13+ requires `POST_NOTIFICATIONS` runtime permission. WorkManager + foreground service for the LDK node when needed (e.g., open channel, claim HTLC). Plan this carefully — Android background restrictions are stricter than iOS background tasks.
- **Test path**: Firebase Console "Send test message" can deliver to a single token, useful for early validation before the full backend integration is live.

## Translation source format

Canonical: **JSON in `shared/strings/`**, one file per locale (`en.json`, `nl.json`, etc.).

Why JSON over YAML/ARB:

- iOS String Catalogs (`.xcstrings`, Xcode 15+) are JSON natively — generation is near-identity transform.
- Android `strings.xml` generation is a simple JSON → XML mapping.
- ICU MessageFormat for plurals/gender works the same on both platforms.
- Hosted CMS option later (Crowdin / Lokalise / Phrase) — all support JSON sync.
- YAML readability isn't worth losing tooling.
- ARB is Flutter-specific; no upside here.

Generator script in `shared/strings/build.{js,py,sh}` runs in CI before each platform build. Source of truth is the JSON; generated files are gitignored or committed (committed is simpler — diff visibility).

Existing iOS `*Language.swift` files get migrated into the canonical JSON in Phase 0 alongside Maestro flow writing — natural opportunity since you're walking every screen anyway.

## Pending technical debt

- **Migrate `accessibilityIdentifier`-as-data usages to `appTag`** (~15 files). The iOS app currently uses `accessibilityIdentifier` as string-tag userInfo for buttons and views (article slugs, settings row IDs, fee levels, tx IDs, IBAN values, swap statuses, value chart spans, view-tag markers). Maestro test IDs need that field reserved. A `UIView.appTag` extension is in place to receive the migrated data. Full file list and rationale in `shared/test-ids/README.md` under "Migrating existing accessibilityIdentifier data usages". Mechanical change, but touches live tap handlers — do per-feature with smoke verification, not bulk find-replace. Until migrated, those screens cannot have full test ID coverage on their data-bearing controls.

## Decisions appendix (all questions resolved)

- **iOS push**: direct APNs (not via Firebase). Backend will dual-send: APNs for iOS, FCM for Android, dispatched by `platform` field on the token record.
- **Regtest infra**: greenfield. Phase 0 includes standing up `bitcoind` + `electrs` + local LDK peer + Boltz testnet wiring, documented in `shared/docs/regtest.md` for reuse during Android development.
