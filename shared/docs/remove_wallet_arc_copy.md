# remove_wallet channel-close arc — copy extracted from source

The 7 screens of the `remove_wallet` channel-close arc cannot be captured in
suite order (`features/remove_wallet.yaml:73` branches on `output.hasChannel`,
which is always false after `suite.yaml:70` restores a channel-less wallet).

This document supplies the exact copy for all 7 from source, so the design
system can be specified without the capture. Every string is quoted verbatim
from `ios/bittr/Language.swift`; every call site is cited.

**Two of the seven are not alerts.** See "Component corrections" below — this
changes what can be built from a component spec and what still needs a shot.

## Component corrections

| Screen | Assumed | Actually |
|---|---|---|
| `04_close_channel_warning` | `BittrAlertSheet` | ✅ alert |
| `05_funds_warning` | `BittrAlertSheet` | ✅ alert |
| `06_channel_closed_popup` | `BittrAlertSheet` | ❌ **QuestionVC** (`question.yellowCard`) |
| `07_closure_initiated` | needs a shot | ✅ **it is an alert** — buildable |
| `08_home_refreshed` | needs a shot | Home, post-refresh state |
| `09_move_lightning_zero` | needs a shot | ❗ Move empty state — genuinely novel |
| `09b_closure_description` | `BittrAlertSheet` | ❌ **TransactionVC** (`transaction.yellowCard`) |

`06` and `09b` are full screens, not alerts — but **both components are already
captured** in the 274 that landed:

- QuestionVC → `settings/` (via `features/settings.yaml:237`)
- TransactionVC → `buy_incoming/`, `swap/`, `send_onchain_all/`, `receive_invoice/`

So for those two the layout is already in the reference set and only the copy
was missing. It is below.

Net: **6 of 7 reduce to copy over an already-specified component.** Only
`09_move_lightning_zero` (Move at zero Lightning balance) is a state no landed
screenshot shows — `send_swap_suggestion_onchain/01a_move_balances` is the one
other Move capture and it asserts `instantSats > 75000`, i.e. deliberately
non-zero.

## Alert button indices

`AlertManager.swift:178` assigns `alert.button.<index>` in array order, so for
`buttons: [.dismiss(a), .action(b)]` → `alert.button.0` = *a*, `alert.button.1`
= *b*. This matches the flow tapping `alert.button.1` to advance.

## The copy

### 04_close_channel_warning — alert
`ResetApp.swift:85`

- **Title** (`removewallet`): `Remove wallet`
- **Message** (`restorewallet4`):
  > Please close your lightning connection(s) before removing your wallet from this device.
  >
  > Otherwise, you may lose access to the funds in your lightning connection.
- **Buttons**: `0` = `Cancel` (`cancel`), `1` = `Close connection(s)` (`closechannel`)

> Note: `remove_wallet.yaml:78` describes this as *"Please close your lightning
> connection(s) before **restoring** a wallet"*. The shipped string says
> **removing**. The comment is stale; the string above is authoritative.

### 05_funds_warning — alert
`ResetApp.swift:150` (`closeChannelAlert`)

- **Title** (`closechannel`): `Close connection(s)`
- **Message** (`closechannel2`):
  > If you close your lightning connection(s), its funds will be deposited back into your wallet.
  >
  > Please wait for this transaction to show up, before definitively removing this wallet from your device.
- **Buttons**: `0` = `Cancel`, `1` = `Close connection(s)`

Note the title is the same string as its own confirm button (`closechannel`).

### 06_channel_closed_popup — QuestionVC, not an alert
`HandlePaymentNotification.swift:369` → `launchQuestion(question:answer:type:)`

- **Question / header** (`closedlightningchannel`): `closed lightning connection`
- **Answer / body** (`closedlightningchannel2`, with `<reason>` substituted):
  > Your lightning connection has been closed.<reason>
  >
  > Any funds that were in this connection are deposited into your bitcoin wallet.
  >
  > To open a new connection with bittr, buy bitcoin worth up to 100 CHF/EUR. Check your wallet's Buy section or getbittr.com for all information.

`<reason>` is replaced by `closedlightningchannel3` + a per-cause clause. For
the cooperative close this arc triggers, that is:

- `closedlightningchannel3`: `" We've been notified that "`
- `locallyInitiatedCooperativeClosure`: `"the connection was closed cooperatively (locally)."`

giving: *"Your lightning connection has been closed. We've been notified that
the connection was closed cooperatively (locally)."*

If no cause matches, `<reason>` is replaced with the empty string — so the
body must render correctly with the sentence ending right after "closed."
There are **15** other `<reason>` clauses (`HandlePaymentNotification.swift:340–362`)
covering force-close, timeout and error paths.

### 07_closure_initiated — alert (buildable, no shot needed)
`ResetApp.swift:235`, the success branch of `closeChannelConfirmed`

- **Title** (`restorewallet`): `Restore wallet`
- **Message** (`stillclosing`):
  > Your Lightning connection is still being closed. For your safety, the wallet can only be reset once the connection is fully closed and the funds have returned on-chain — this can take a while.
  >
  > Please reopen the app later to finish the reset. Do not delete the app from your phone, as this will lead to loss of funds.
- **Buttons**: `0` = `Okay` (`okay`) — single button

> Two stale references corrected here. `remove_wallet.yaml:127` calls this the
> `closechannel5` alert reading *"Connection closure initiated…"*. **There is no
> `closechannel5` key in `Language.swift`** and no such copy anywhere in the app.
> The actual alert is the `stillclosing` text above.
>
> Separately: this alert is titled **"Restore wallet"**, while `ResetApp.swift:103`
> shows the *same* `stillclosing` message titled **"Remove wallet"**. That is a
> genuine inconsistency in the shipped app, not a transcription error — worth a
> copy decision rather than baking both into the design system.

### 08_home_refreshed — Home
Standard Home after pull-to-refresh; on-chain balance now includes the closure
payout and Lightning is zero. Home layout is captured 6× in the landed set
(e.g. `onboarding/20_home.png`).

### 09_move_lightning_zero — Move, empty state ❗
`move.satsInstant` reads exactly `0 sats`. `MoveViewController.updateLabels`
formats it as `String(satoshisLightning).addSpaces() + " sats"`, so the literal
rendering at zero is `0 sats` — no special empty-state copy, the same label at
value zero.

This is the one screen with no equivalent in the landed 274. If any single shot
is worth chasing, it is this one.

### 09b_closure_description — TransactionVC, not an alert
`Language.swift:592`, surfaced by `TransactionVC.descriptionText()` when a
transaction has no Lightning description and its txid is in the channel-closure
cache.

- **Description label** (`channelclosuretransaction`):
  > These are the funds from your closed lightning connection, returning to your regular wallet.

The flow asserts on `.*closed lightning connection.*`, which this satisfies.

## Related strings in the same arc (not screenshotted, same surface)

Reachable failure branches the design system should expect:

| Key | Copy | Site |
|---|---|---|
| `closechannel6` | `Connection Closure Issue` | `ResetApp.swift:210` title |
| `closechannel7` | `The lightning connection could not be closed normally, possibly because the bittr node is offline or there's a connection issue.\n\nYou can close the connection unilaterally (force close), but this will require higher transaction fees and may take longer to complete.` | `ResetApp.swift:210` message |
| `forceclose` | `Force Close` | `ResetApp.swift:210` button 1 |
| `closeretrylater` | `Your Lightning connection could not be closed right now — the bittr node may be temporarily offline. Your wallet has not been reset.\n\nPlease reopen the app to try again later. Do not delete the app from your phone, as this will lead to loss of funds.` | `ResetApp.swift:175, 206` |
| `restorewallet2` | `Are you sure you'd like to remove this wallet from your device?\n\nOnly remove your wallet if you're sure you've properly backed up your wallet.` | `ResetApp.swift:115` — captured as `10_restore_confirm_1` |
| `restorewallet3` | `Are you sure you want to remove your wallet from this device?` | `ResetApp.swift:146` — captured as `11_restore_confirm_2` |
| `closechannel3` | `Your lightning connection has been closed. Wait for any remaining funds to reappear in your wallet before removing this wallet from your device.` | **no call site found** — appears dead |
| `closechannel4` | `We could not close your lightning connection. Please try again.` | **no call site found** — appears dead |

`remove_wallet.yaml:265` also references a `restorewallet5` alternate for
`10_restore_confirm_1`; **no such key exists** in `Language.swift`. Third stale
reference in the same file.
