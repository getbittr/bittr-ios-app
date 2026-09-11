# Play Store screenshots: the capture procedure

The Play Store screenshot set **must be captured with CHF explicitly selected**. This
document is the procedure for doing that, written to be followed rather than
re-derived. It comes from BIT-47, which carries the requirement forward from BIT-37.

> **Status: not yet performed.** No store screenshot set exists. The Android port has
> no screen that displays a fiat amount yet — `BittrNavHost.kt` routes to
> `signup/start` and nothing else — so there is nothing to capture. This document
> exists so the requirement is in place before the screens are, not after.

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

## When the Android screens land

The same trap applies to the port unless it defaults differently. Two things to do
when the first fiat-displaying Android screen is built:

1. **Do not port the `?? "EUR"` fallback.** There is no reason for the Android app to
   have a euro default at all — the app ships to Switzerland only (BIT-37). Make the
   currency non-optional, or default it to CHF.
2. `CurrencyDefaultGuardTest` (`android/app/src/test/.../CurrencyDefaultGuardTest.kt`)
   fails the build if a euro default is introduced into `main` sources. It scans for
   fallback and default-assignment syntax, so it stays quiet about a currency picker
   that legitimately *lists* EUR as an option. If it fires, fix the default — do not
   add an exemption so a store capture can be taken around it.

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
euro-denominated screenshot is worse than a missing one — it is public copy stating a
currency the app does not serve. A shorter set is an acceptable outcome of this
procedure.

## Procedure

1. **Install and reach a wallet-ready state** on the capture device.
2. **Select CHF**: Settings → the currency row (`settings.row.currency` /
   `device.row.currency` in `TestIDs.kt`) → **CHF**. On iOS this is
   `DeviceViewController.changeCurrency()`.
3. **Verify the selection took**, before capturing anything — the currency control on
   Home / Send / Receive (`home.currencyButton`, `send.currencyLabel`,
   `receive.currencyLabel`) must read `CHF`. If it reads `€` or `EUR`, stop; step 2
   did not apply.
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
