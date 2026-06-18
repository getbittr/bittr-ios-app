# Parity tracker

Per-feature status of iOS vs Android implementation. Updated as Maestro flows go green on each platform.

| Feature | iOS | Android | Maestro flow | Notes |
|---|---|---|---|---|
| Test-ID smoke | done | n/a | `onboarding/smoke.yaml` | Verifies the JSON → build.py → Swift → Maestro pipeline reaches a real ID. |
| Onboarding (create wallet + bittr signup) | done | not started | `onboarding/happy_path.yaml` | Top-level entry: `onboarding/fresh_install.yaml` (wipes state, runs happy_path). |
| Buy — first incoming bank transaction | done | not started | `features/buy_incoming.yaml` | Opens the lightning channel; needs `fresh_install` first. |
| Buy — subsequent top up | done | not started | `features/buy_more.yaml` | Preserves wallet state; needs prior `buy_incoming` run for the channel. Requires `scripts/push_server.js` running. |
| Receive | done | not started | `features/receive.yaml` | Auto-recovers via `onboarding/happy_path.yaml` if launched on a clean install. |
| Swap (lightning ↔ onchain, both directions) | done | not started | `features/swap.yaml` | Re-uses existing channel + onchain balance from prior buy flow. |
| Bitcoin value chart | done | not started | `features/bitcoin_value.yaml` | Opens from Home's currency icon; waits for price data, scrubs the graph, switches span m/y/5y. Needs an existing wallet (unlocks with PIN). |
| Pin unlock (subflow) | done | not started | `helpers/unlock.yaml` | Called by feature tests when the app launches into the unlock screen. |

## Not yet covered by flows

iOS-side screens that still need a flow before they're parity-tracked: Send (onchain + lightning), Restore wallet, Settings, Map, Academy, Profits, Widget, LNURL-Auth.

## Legend

- `done` — feature is shipped and Maestro flow passes
- `wip` — actively being ported
- `not started` — Android implementation not begun
- `blocked` — waiting on something (note in description)
- `n/a` — intentionally platform-specific (e.g., iOS Widget vs Android Glance equivalent tracked separately)
