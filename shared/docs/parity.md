# Parity tracker

Per-feature status of iOS vs Android implementation. Updated as Maestro flows go green on each platform.

| Feature | iOS | Android | Maestro flow | Notes |
|---|---|---|---|---|
| Test-ID smoke | done | n/a | `onboarding/smoke.yaml` | Verifies the JSON → build.py → Swift → Maestro pipeline reaches a real ID. |
| Onboarding (create wallet + bittr signup) | done | not started | `onboarding/happy_path.yaml` | Top-level entry: `onboarding/fresh_install.yaml` (wipes state, runs happy_path). |
| Buy — first incoming bank transaction | done | not started | `features/buy_incoming.yaml` | Opens the lightning channel; needs `fresh_install` first. |
| Buy — subsequent top up | done | not started | `features/buy_more.yaml` | Preserves wallet state; needs prior `buy_incoming` run for the channel. Requires `scripts/push_server.js` running. |
| Receive | done | not started | `features/receive.yaml` | Auto-recovers via `onboarding/happy_path.yaml` if launched on a clean install. |
| Receive onchain → Send round-trip | done | not started | `features/receive_onchain.yaml` | Shows the onchain address (waits out the verification spinner), copies it, pastes into Send asserting Regular/onchain with and without a 5000 sat amount, then renews until the address pool is exhausted. Uses `helpers/show_onchain_address.yaml`. |
| Receive invoice → Send round-trip | done | not started | `features/receive_invoice.yaml` | Switches the type to a lightning invoice, copies it, pastes into Send asserting lightning with and without a 2000 sat amount. Requires an active channel. Uses `helpers/show_invoice.yaml`. |
| Swap (lightning ↔ onchain, both directions) | done | not started | `features/swap.yaml` | Re-uses existing channel + onchain balance from prior buy flow. |
| Bitcoin value chart | done | not started | `features/bitcoin_value.yaml` | Opens from Home's currency icon; waits for price data, scrubs the graph, switches span m/y/5y. Needs an existing wallet (unlocks with PIN). |
| Bitcoin map | done | not started | `features/bitcoin_map.yaml` | Opens from Home's map icon; waits for the btcmap sync, opens/closes a place, moves the map, recentres on user. Grants location via launchApp; needs an existing wallet (unlocks with PIN). |
| Academy | done | not started | `features/academy.yaml` | Opens the Academy tab, plays the latest available lesson to completion (paging Next→Complete, waiting on image-download spinners), then opens the next unlocked lesson. Needs an existing wallet (unlocks with PIN). |
| Pin unlock (subflow) | done | not started | `helpers/unlock.yaml` | Called by feature tests when the app launches into the unlock screen. |

## Not yet covered by flows

iOS-side screens that still need a flow before they're parity-tracked: Send end-to-end (broadcast/confirm — onchain paste + parsing is exercised by `features/receive_onchain.yaml`, but the Confirm → send path and lightning sends are not), Restore wallet, Settings, Profits, Widget, LNURL-Auth.

## Legend

- `done` — feature is shipped and Maestro flow passes
- `wip` — actively being ported
- `not started` — Android implementation not begun
- `blocked` — waiting on something (note in description)
- `n/a` — intentionally platform-specific (e.g., iOS Widget vs Android Glance equivalent tracked separately)
