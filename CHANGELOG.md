# Changelog

All notable changes to the bittr iOS app are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project aims to adhere to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

We started tracking the changelog at **0.1.184** (the TestFlight build current when this file was added); earlier releases are not itemized here. Changes land under `[Unreleased]` and are renamed to the version + date when a TestFlight build is cut.

## [Unreleased]

### Added

- **The exclusive-initiative confirmation required by Terms & Conditions §2.5** is now collected in the app. It is asked once per registration, on the IBAN + email screen, before the IBAN and email are sent to Bittr — the first moment Bittr provides a Service. The wording is taken from §2.5 and the getbittr.com interstitial (sources and the exact departures are recorded in `shared/docs/exclusive-initiative-copy.md`). The confirmation is timestamped (ISO-8601, UTC), stored against the IBAN entity, and sent to the backend as `exclusive_initiative_confirmed_at` at registration. Declining leaves the customer on the screen with nothing sent and nothing recorded. The website has had this since launch; the apps never did.

## [0.1.185] - 2026-09-08

### Added

- **Swap Live Activity in the Dynamic Island and on the Lock Screen** for onchain→lightning swaps: a boarding-pass-style status with a live elapsed timer and progress bar, updated in real time, that deep-links back into the app — including the incoming-payment (HTLC-resume) flow during the final leg so the wallet comes online to receive. (#89)
- Payout errors `PAYMENT_PROCESSING` and `PAYMENT_TOO_LARGE` are now handled explicitly and close-only (no retry). `PAYMENT_PROCESSING` prevents a double-payment when a payout is committed but its outcome is still ambiguous.
- BTCMap.org attribution on the Bitcoin map. (#87)

### Changed

- Production Electrum server switched to bittr's own (`ssl://esplora.getbittr.com:50002`) instead of Blockstream's public server.
- Entering the shown swap **maximum** now works: onchain→lightning drains the on-chain wallet (fee-aware), and lightning→onchain caps at outbound capacity minus the Boltz fee, claim fee, and a small routing headroom. (#89)
- The Home screen refreshes when a swap completes, merging the on-chain and lightning legs into a single row instead of leaving a stale outgoing payment behind. (#89)
- Friendlier, consumer-facing error messages throughout the Send flow, with guards against sending to the wrong network or paying your own invoice; unsupported BOLT12 offers are rejected up front. (#80)
- Remaining system alerts and action sheets replaced with the app's own alert style (LNURL withdraw amount, receive currency picker). (#90)
- Improvements to the app launch animation. (#85)
- The RegisterIban screen uses the standard header and supports dark mode. (#78)

### Fixed

- The swap flow no longer hangs when the Boltz fee API is unreachable, and the loading spinner is always cleared on failure. (#81, #88)
- The Bitcoin map re-downloads the full dataset when nothing is cached. (#86)
- Swept a class of `try!` crashes in the swap refund/claim, key-derivation and message-signing paths; alert rendering (`String.attributed()`) falls back to plain text instead of crashing when run off the main thread. (#89)
- Fixed an `NSInvalidArgumentException` when opening the swap status screen from a Dynamic Island / silent-push tap. (#89)
- On-chain payouts are broadcast off the main thread. (#73)

### Security

- Boltz swap responses are validated before any satoshis are sent — the invoice, the lockup address, and the reverse-swap claim leaf are checked against our own keys/preimage, so a tampered Boltz response can't misdirect funds. (#79, #89)
- Confined LightningDevKit usage to a single file, reducing the dependency's surface area. (#88)

### Internal / tests

- Refactors with no user-facing change: SendVC, ValueVC, the PIN keypad, balance-label rendering, and caching; console logging is centralized and kept out of release builds. (#69, #70, #71, #72, #80, #83, #84)
- Maestro end-to-end suite: `test_suite.sh` now runs the full `suite.yaml` in order (with a `--from` flag to resume after a failure); added reverse-swap lockup validation unit tests; fixed several flow/permission issues surfaced by running the full suite.
