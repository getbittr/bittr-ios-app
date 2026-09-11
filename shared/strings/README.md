# Strings

Canonical i18n source for both apps. One JSON file per locale (`en.json`, `nl.json`, …). A generator script produces `Localizable.xcstrings` for iOS and `strings.xml` for Android.

Plurals and gender variations use ICU MessageFormat (understood by both platforms).

## Migration plan

The iOS app's copy lives in **one** table: `allWords` in `ios/bittr/Language.swift`, 572 keys. The other ten `*Language.swift` files hold no copy at all — they are `setWords()` / `changeColors()` extensions that call `Language.getWord(withID:)`, so they are consumers, not sources. Phase 0 walks each screen for Maestro flows; while there, the strings get migrated into the canonical JSON.

What *is* scattered is the copy that never made it into `allWords` — see "Copy outside the table" below. That is the part a migration of `allWords` alone will walk past.

### The consolidation is verbatim

**Moving copy is in scope. Rewording it in the same change is not.** If a string has to change, change it in a separate commit, so that when a flow goes red the cause is obvious.

This is not a style preference. The Maestro suite identifies alerts by their **copy**, because copy is the only thing available to identify them by: `alert.button._index` and `alert.textField` are the only accessibility ids on the alert surface. Measured on the current suite:

- **220** `alert.button` / `alert.textField` interactions across **33** flow files
- **147** `text:` matchers, **71** of them distinct, across **24** flow files
- **39** of those 71 are app copy: they depend on **37** keys in `allWords` and **7** hardcoded literals

A word changed in transit breaks those assertions **silently** — a copy change isn't a behaviour change, so nobody expects a test result from it — and, once both apps read this directory, **on both platforms at once**. The failure then looks like an Android port bug, weeks later.

### The guard

`check_flow_copy.py` pins every text the suite matches on to the copy it depends on, and re-resolves that lock against whichever source is present: `ios/bittr/Language.swift` before the move, `shared/strings/en.json` after it. Same lock, both sides of the migration commit:

```sh
./shared/strings/check_flow_copy.py                             # before: green
# … do the move …
./shared/strings/check_flow_copy.py                             # after: green == verbatim
./shared/strings/check_flow_copy.py --source ios/bittr/Language.swift   # pin the source explicitly
./shared/strings/check_flow_copy.py --update                    # re-lock after a deliberate copy change
./shared/strings/test_check_flow_copy.py                        # prove the guard still bites
```

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

Seven strings the suite asserts on are **not** in `allWords`, so a search-and-move of that table will not find them. They are locked as `literals` — text that must still appear, quoted, in a named file:

| copy | where it lives | the flow that depends on it |
| --- | --- | --- |
| `Copy` | `ReceiveViewController.swift` — `UIAction(title:)` on the QR long-press menu | `receive_onchain.yaml` |
| `Share` | `ReceiveViewController.swift` — the other `UIAction` on that menu | `receive_onchain.yaml` |
| ` sats` | `MoveViewController.swift` — `"\(instantSatoshis)".addSpaces() + " sats"` | `remove_wallet.yaml` |
| `Swap complete` | `SwapLiveActivity.swift` **and** `SwapLiveActivityController.swift` — a third copy of the `swapstatusswapcomplete` key | `swap.yaml`, `send_swap_suggestion_onchain.yaml` |
| `Syncing wallet to get updated channel count` | `ResetApp.swift` — a third copy of `syncingwallet` / `syncingwallet3` | `notification_htlcincoming.yaml`, `notification_lnurl.yaml` |
| `You can send 0 satoshis.` | `Main.storyboard` — the label's design-time text, which is what a flow sees before the first render | `send_onchain.yaml` |

Two of those are the same sentence stored three times (`Swap complete`, `Syncing wallet`). Collapsing each into one key is the right end state and the consolidation is the moment to do it — but as a deliberate commit: all three copies of each are locked, so a silent dedup goes red rather than quiet.

### Longer term

Give the alert surface real per-alert accessibility ids, so assertions stop depending on wording at all. Not required before the migration; the migration is what proves why it is needed.

## Generator

To be added (`build.{js,py,sh}`). Runs in CI before each platform build, and on demand during dev. Generated platform files are committed for diff visibility.

`check_flow_copy.py` reads `en.json` flat or nested (dotted keys), and ignores keys starting with `_`, so a metadata header in the locale file is fine.
