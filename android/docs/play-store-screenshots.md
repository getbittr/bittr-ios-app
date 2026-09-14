# Play Store screenshots: the capture procedure

The Play Store screenshot set **must be captured with CHF explicitly selected**. This
document is the procedure for doing that, written to be followed rather than
re-derived. It comes from BIT-47, which carries the requirement forward from BIT-37.

> **Status: not yet performed, and step 2 does not currently work on Android.**
> No store screenshot set exists.
>
> An earlier revision of this note said the port had no screen displaying a fiat
> amount. That is **no longer true**: the Bitcoin value screen (BIT-99) renders one —
> `ValueScreen.kt:82` draws `"${currency.symbol} ${formatPrice(...)}"` above the chart,
> and the scrub card repeats the symbol via `ValueCopy.currencySymbol`.
>
> It is, however, **hard-wired to euro and cannot be switched to CHF by any user
> action** — see *The Value screen ignores the currency setting* below. So the capture
> is still blocked, but on that defect rather than on the absence of a screen.

## The rule, in one line

Select CHF **before** capturing. Do not capture and check afterwards.

## Why: a clean device silently produces euros

The currency is read from a cache that a fresh install does not have. On iOS every
read site falls back to EUR:

| Site | Code |
|---|---|
| `ios/bittr/Move, Send, Receive/ReceiveVC/ReceiveViewController.swift:564` | `CacheStore.value(for: CacheKeys.currency) ?? "EUR"` |
| `ios/bittr/Move, Send, Receive/SendVC/Send/SendViewController.swift:264` | `CacheStore.value(for: CacheKeys.currency) ?? "EUR"` |
| `ios/bittr/Move, Send, Receive/SendVC/Send/SendVCTextFields.swift:62` | `CacheStore.value(for: CacheKeys.currency) ?? "EUR"` |
| `ios/bittr/Transaction/Transaction.swift:32` | `var currency = "EUR"` (and `:83`, same default on decode) |

Exactly one site branches to CHF — `ios/bittr/Helpers/BittrWallet.swift:42`:

```swift
bitcoinValue.currentValue = self.valueInEUR ?? 0.0
if CacheStore.value(for: CacheKeys.currency) == "CHF" {
    bitcoinValue.currentValue = self.valueInCHF ?? 0.0
    bitcoinValue.chosenCurrency = "CHF"
    bitcoinValue.apiUrl = "https://getbittr.com/api/price/btc/historical/chf"
}
```

That branch only fires **once the cache has been set**. So a capture run on a clean
device shows the euro symbol, no warning, no failure — the screenshots just come out
wrong. This is the trap the whole issue is about.

### The cache value is `€` or `CHF` — never the string `EUR`

`DeviceViewController.swift:118` writes the *symbol* for euro and the *code* for
franc:

```swift
.action("EUR €") { self.selectCurrency("€") },
.action("CHF")   { self.selectCurrency("CHF") }
```

So there are three distinct states, and only the third is safe to ship:

| Cache | Displays | Safe? |
|---|---|---|
| unset (fresh install) | EUR default via the `?? "EUR"` fallbacks | **No** |
| `"€"` | euro | **No** |
| `"CHF"` | franc, CHF price feed | Yes |

A verification step that checks `cache == "CHF"` is correct. One that checks
`cache != "EUR"` passes in all three states and proves nothing.

Note that CHF also switches the price endpoint (`/api/price/btc/historical/chf`). A
capture run with mocked pricing must mock the CHF URL, or the amounts render from a
euro-denominated feed even with CHF selected.

## The Value screen ignores the currency setting

This is the defect that currently blocks the capture, and it is also a plain
user-facing bug. Verified by code read on `android-parity` at `c7f67583`:

- `AppPreferences.currency` is the app-wide EUR/CHF setting. The Device screen writes
  it (`DeviceScreen.kt:149-153`) and it persists.
- Its **only** readers are `MainActivity` (theme) and `DeviceViewModel` (the picker
  that writes it). **Nothing reads it to display an amount.**
- The value screen takes its own, unrelated `PriceCurrency` parameter defaulting to
  euro (`ValueScreen.kt:55`, `:67`), and `BittrNavHost.kt:195` constructs it as
  `ValueScreen(onBack = ...)` — passing nothing. So it is always `PriceCurrency.EUR`.
- `PriceCurrency` is referenced nowhere outside `feature/value`. The two currency
  types are never connected.

Consequence: selecting **CHF** in Settings changes nothing on the value screen. It
keeps the `€` glyph *and* keeps fetching the euro series (`btc_eur`,
`/historical/eur`). Steps 2–3 of the procedure below cannot be satisfied for this
screen today — not because the operator might forget, but because there is no input
that would change the result.

**Fix before capturing:** feed the selected `AppPreferences.currency` into
`ValueScreen` (map `Currency` → `PriceCurrency` at the nav host, or read the
preference inside the feature). Do not work around it by capturing this screen in
euro — see *No fiat amount is a substitute for a wrong one*.

## `CurrencyDefaultGuardTest` is green, and blind

`CurrencyDefaultGuardTest` (`android/app/src/test/.../CurrencyDefaultGuardTest.kt`)
was written to fail the build if a euro default reached `main` sources. It currently
**passes over all 123 main sources while five euro defaults are present**, because its
regex matches only *quoted string literals* (`?: "EUR"`, `= "€"`) and the port
expresses its defaults as *typed enum constants*:

| Site | Line |
|---|---|
| `core/preferences/.../AppPreferences.kt:79` | `val DEFAULT_CURRENCY = Currency.EUR` |
| `feature/settings/.../DeviceViewModel.kt:29` | `val currency: Currency = Currency.EUR,` |
| `feature/value/.../ValueCopy.kt:41` | `?: PriceCurrency.EUR.symbol` |
| `feature/value/.../ValueScreen.kt:55` | `currency: PriceCurrency = PriceCurrency.EUR,` |
| `feature/value/.../ValueScreen.kt:67` | `currency: PriceCurrency = PriceCurrency.EUR,` |

Extending the alternation to `(?:[A-Za-z_][A-Za-z0-9_]*\.)*EUR\b` catches exactly
these five and nothing else (checked against all 123 files; the enum *declarations*
`EUR("EUR", "€", "EUR €")` and `EUR("€", "eur", "btc_eur")` are positional
constructor calls with no `=`, so they stay quiet, which is correct — offering EUR is
a product choice, defaulting to it is the thing being guarded).

> **Do not simply tighten this guard and walk away.** Its stated rationale is *"the
> app ships to Switzerland only (BIT-37)"*, and **that premise is superseded** —
> availability is worldwide as of Ruben's 2026-09-10 decision (`perimeter` v1.1 §6).
> Whether a worldwide, iOS-parity wallet should default to EUR is now a product
> question and not settled here. What is *not* in question is BIT-37 §4, explicitly
> preserved through that decision: **the screenshot set is captured with CHF
> selected.** That needs CHF to be *selectable and effective*, which is the section
> above — it does not need the default to change.

## `FLAG_SECURE` blanks a capture without failing it

The recovery-phrase screen uses `FLAG_SECURE` (Android's answer to the iOS
screenshot-warning notification — see `shared/docs/parity.md`). A `FLAG_SECURE`
window is captured as a **black frame** by `adb screencap`, which is what Maestro's
`takeScreenshot` drives. It does not error. The PNG is written, the flow goes green,
and the file is blank.

`ScreenshotBlockingGuardTest` already enforces that the flag is never set app-wide,
for exactly this reason. That guard does not help here: a correctly scoped
`DisposableEffect` still blanks **the screen it is scoped to**. So:

> No store screenshot may come from the recovery-phrase screen, or from any screen
> that sets `FLAG_SECURE`.

The black-frame check in the verification step below catches this if it happens
anyway.

## No fiat amount is a substitute for a wrong one

If a screen cannot be captured with CHF showing, **leave it out of the set**. A
euro-denominated screenshot is worse than a missing one: it is public copy, it
contradicts the CHF-denominated Terms, and BIT-37 §4 requires CHF whatever the store's
country availability turns out to be. A shorter set is an acceptable outcome of this
procedure.

## Procedure

1. **Install and reach a wallet-ready state** on the capture device.
2. **Select CHF**: Settings → the currency row (`settings.row.currency` /
   `device.row.currency` in `TestIDs.kt`) → **CHF**. On iOS this is
   `DeviceViewController.changeCurrency()`.
3. **Verify the selection took on the screen you are about to capture** — not just in
   Settings. Read the fiat amount on that screen itself; it must show `CHF`. If it
   shows `€` or `EUR`, stop; the selection did not reach it.

   > Verifying only in Settings is not sufficient, and this is not hypothetical: the
   > value screen shows the Settings row reading `CHF` while the chart above it stays
   > in euro (see *The Value screen ignores the currency setting*). Check the amount,
   > not the setting.

   On Home / Send / Receive the control to read is `home.currencyButton`,
   `send.currencyLabel`, `receive.currencyLabel` (`TestIDs.kt`). Note that as of
   `android-parity` `c7f67583` these three are **test-ID constants for screens that do
   not exist yet** — Home's send/receive/balance routes are stubs behind BIT-6/BIT-7.
   The value screen is the only fiat-displaying screen currently built.
4. **Capture the set.** Skip any screen that sets `FLAG_SECURE`.
5. **Verify the output** (below).
6. **Send the set to Compliance** (below) and wait for acceptance.
7. **Upload** only after acceptance.

### Verifying the output

Both checks are mechanical; run them on the whole directory before sending anything.

- **No black frames.** A `FLAG_SECURE` capture is uniformly black:

  ```sh
  # Any file whose mean pixel value is ~0 is a blanked capture, not a screenshot.
  for f in <set-dir>/*.png; do
    printf '%s ' "$f"; magick "$f" -format '%[fx:mean]' info:; echo
  done
  ```

- **No euro anywhere.** Check both the glyph and the code, since the app uses `€` in
  the UI and `EUR` in the fallback strings. These are images, so this needs OCR:

  ```sh
  for f in <set-dir>/*.png; do
    tesseract "$f" - 2>/dev/null | grep -n '€\|EUR' && echo "  ^ euro in $f"
  done
  ```

  OCR is a backstop for a mistake in step 2/3, not the primary control — the primary
  control is selecting CHF up front. Eyeball the set as well.

### Compliance review is required before upload

Screenshots are copy and are reviewed as copy: **Tier 1 item 1** in the `perimeter`
document on BIT-27. Send the set to the Compliance & Regulatory Officer and wait for
acceptance before uploading to Play Console. Every later change to a
publicly-used screenshot is **Tier 2** thereafter.

## Where the set lives

Store screenshots are a curated, reviewed artefact and are **not** the same thing as
the Maestro flow captures under `shared/flows/.maestro/screenshots/`, which are test
evidence. Put the reviewed store set in `shared/docs/screenshots/` under a directory
that names it as such, and keep the Compliance acceptance reference with it.
