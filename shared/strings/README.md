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

`check_flow_copy.py` reads `en.json` flat or nested (dotted keys), and ignores keys starting with `_`, so a metadata header in the locale file is fine.
