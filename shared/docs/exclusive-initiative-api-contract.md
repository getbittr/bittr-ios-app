# `exclusive_initiative_confirmed_at` — client/server contract

The wire contract for the T&C **§2.5** exclusive-initiative confirmation: what a client sends,
what the server must do with it, and what neither side may do. Cross-platform on purpose —
iOS sends this today and the Android port will send the same field, so the rules live here
rather than in either app's code.

Copy — the sentence the customer actually reads, and where the sheet appears — is
`shared/docs/exclusive-initiative-copy.md`. This file is only the contract; the two change
independently, and a copy revision never changes anything below.

## The field

| | |
|---|---|
| Name | `exclusive_initiative_confirmed_at` — identical on the wire, in the column, and in any admin view. No rename, no mapping layer, no per-platform variant. |
| Type | String, ISO-8601, **UTC**, second precision, literal `Z` suffix — `2026-09-11T12:50:45Z`. Not fractional seconds, not `+00:00`, not device-local. |
| Request | `POST {bittrAPIBaseURL}/customer` — `https://getbittr.com/api/customer`, staging `https://staging.getbittr.com/api/customer`. JSON body, `Content-Type: application/json`. |
| When there is no confirmation | **The key is omitted entirely.** Not `null`, not `""`, not a back-filled value. |
| Absent means | **Not confirmed.** Never "confirmed at epoch", never a validation error. |

## Why "absent" has to stay safe

An account registered before the app collected this has nothing truthful to send. If the
server treats a missing key as an error, every pre-existing registration breaks; if it
substitutes a value, the record says a customer confirmed when they did not — which is worse
than having no record, because it is a false one.

This is not the same question as whether Bittr should *refuse* to serve an unconfirmed
customer. That is open (BIT-27 Q3, with counsel) and is deliberately not answered here.
Until it is answered, the column stays nullable and nothing rejects a registration for
lacking the field.

## Client rules

Binding on iOS and on the Android port equally.

1. **Send the moment of confirmation, in UTC**, formatted as above. UTC and not the device
   zone so that what is stored is unambiguous wherever the customer was.
2. **Omit the key when there is nothing to send.** Guard on non-nil *and* non-empty.
3. **Never invent one.** No `now()` at registration time, no default, no value derived from
   anything other than the customer actually confirming.
4. **Treat the local copy as a cache, not as the record.** The device's stored timestamp is
   an optimisation so a returning customer isn't re-asked. The record is the server's.

### iOS, as implemented

On `feature/bit-50-exclusive-initiative` (verified at `04e9336`):

- Emitted in `Transfer2ViewController.swift:376-378`, guarded non-nil and non-empty, so the
  key is omitted rather than sent blank.
- Formatted by `Transfer1ViewController.confirmationTimestamp()` — an `ISO8601DateFormatter`
  with `timeZone` forced to GMT and `formatOptions = [.withInternetDateTime]`, which is
  exactly `yyyy-MM-dd'T'HH:mm:ssZ` in UTC.
- Cached as `IbanEntity.initiativeConfirmedAt`, `String?` on purpose, so an entity written
  before the feature decodes to `nil` instead of discarding the stored IBAN entity.

### Android, when the port reaches signup

Not yet implemented — `android/` holds store listing assets only. The equivalent of the
formatter above is:

```kotlin
// UTC, second precision, trailing Z — matches ISO8601DateFormatter([.withInternetDateTime])
DateTimeFormatter.ISO_INSTANT.format(Instant.now().truncatedTo(ChronoUnit.SECONDS))
```

`ISO_INSTANT` already emits `Z` rather than `+00:00`; the `truncatedTo` is what drops the
fractional seconds Java would otherwise include. Omit the key — don't serialise `null` —
when there is no confirmation.

## Server rules

The backend is not in this repository. These are the requirements it has to meet; the full
implementation spec, with reference Postgres DDL, is the `exclusive-initiative-persistence`
document on BIT-86.

**1. Persist it against the customer**, as sent, zone-aware (`timestamptz`, not a zone-naive
column — a Swiss host reinterpreting a UTC string costs one or two hours of drift on a field
whose entire purpose is answering *when*). Nullable, no default, no back-fill.

**2. Make it retrievable.** A write that is accepted and then cannot be read back fails §2.5
exactly as dropping it does. Bittr has to be able to answer "did this customer confirm, and
when?" for a named customer, and "how many customers have no record?" across the population.

**3. Absent must not clear a stored value, and the first confirmation wins.**
`POST /customer` is *not* create-only — the signup flow reuses an existing `deposit_code` on
recovery (`Transfer2ViewController.swift:385-388`) precisely so the server updates the
existing customer instead of opening a second order. So the handler that first stores this
field is later re-entered for a customer who already has one:

- A recovery on a build predating the feature sends no key; assigning the parameter
  unconditionally writes `NULL` over a real confirmation.
- A recovery on a *new device* sends the timestamp cached on that device — minutes ago, not
  when the customer actually confirmed. Overwriting moves the compliance record forward and
  loses the true date.

Both are one expression: `COALESCE(stored, incoming)`. Write-once, then immutable; a
legitimate correction is a support action with an audit trail, not a side effect of a
registration retry.

**4. Don't couple it to a client.** One field, one column, no `ios_`/`android_` split and no
branch on platform. The confirmation is a property of the customer's contract with Bittr, not
of the device it was collected on. A customer who confirms on iOS and later reinstalls on
Android must still read as confirmed — with their original timestamp, which rule 3 is what
preserves.

## Optional, additive: echo it back

Returning `exclusive_initiative_confirmed_at` in the `POST /customer` response and in
`GET /deposit_code?timestamp=&signature=&pubkey=` (already the authenticated recovery read)
would let a recovering client restore the confirmation into its own cache instead of
re-asking a customer who already confirmed. That matters more once there are two clients: a
customer moving iOS → Android has no local cache to recover from by definition, so the server
is the only thing that can tell them apart from someone who never confirmed.

Additive and safe to ship separately: iOS reads its response dictionary key-by-key with `as?`
casts (`CallsManager.makeApiCall` hands back an `NSDictionary`), so an unknown extra key is
ignored rather than fatal. No version bump.

## Not in scope

No validation that rejects a registration without the field, and no later `NOT NULL`
migration — making the column mandatory is the same decision as rejecting unconfirmed
registrations, taken through the schema instead of through the validator. That decision waits
on counsel (BIT-27 Q3).
