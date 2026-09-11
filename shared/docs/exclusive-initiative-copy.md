# Exclusive-initiative confirmation — copy sources

The strings at `ios/bittr/Language.swift:175-177` are not authored. They are assembled from
two documents Bittr already publishes. This file records which sentence came from where, and
every place the app's wording departs from the source — so a reviewer can check the copy
without re-reading the live site, and so a later edit knows what it is allowed to touch.

**Do not reword any of these strings without the Compliance & Regulatory Officer.** It is a
Tier 1 trigger on BIT-27. This file is the thing to bring to that conversation.

## Sources

Both fetched from production on **2026-09-11**. Both are subject to change without anyone
telling us; re-fetch before relying on this file.

| Ref | Source |
|-----|--------|
| **§2.5** | `getbittr.com/terms-and-conditions` § 2.5 *Important provisions for EU residents*. Terms version **1.1 – 28 December 2024**. |
| **INT** | The geo-IP interstitial rendered on every `getbittr.com` page, under the headings *Notification for non-Swiss users* / *Regulatory Information*. |

## The three strings

### `initiativetitle` — sheet heading

> Your own exclusive initiative

**This is the one string with no source.** Neither INT heading works in the app: *"Notification
for non-Swiss users"* presumes a geo-IP result the app does not have and must not acquire
(out of scope, BIT-50 item 4), and *"Regulatory Information"* describes the middle paragraph
rather than the thing being asked of the customer. The phrase used is lifted from §2.5's own
words but the heading itself is ours.

If a reviewer would rather ship only quoted text, **"Regulatory Information"** is the
drop-in that needs no judgement. Flagged for decision, not assumed.

### `initiativemessage` — sheet body, three paragraphs

**Paragraph 1 — from INT, one substitution.**

> Bittr AG operates in compliance with Swiss regulations. The products and services ~~showcased
> on this website~~ **offered by Bittr AG** are authorized for promotion and sale within
> Switzerland. Without express authorization from the regulatory authority of a given country,
> Bittr AG is not permitted to actively promote its products and services in that territory.

`showcased on this website` → `offered by Bittr AG`. There is no website here. Left verbatim
it would be false in the app, and it would read as covering a surface the customer is not on.

**Paragraph 2 — from INT, verbatim apart from a dropped label.**

> ~~IMPORTANT NOTE:~~ If you are located in the European Union, Bittr AG will not be authorized
> to provide services to you unless you request the service on your exclusive initiative.

`IMPORTANT NOTE:` dropped — it is typography for a wall of text on a web page, and the sheet
is already three paragraphs long. The sentence itself is unchanged.

**Paragraph 3 — from §2.5, verbatim.**

> Before we can provide any Services to you, we'll need you to confirm that your request is
> made solely on your own exclusive initiative, without any encouragement or solicitation
> from us.

Word for word, including `Services` capitalised as the Terms define it. The only difference
is the apostrophe: the site renders `we’ll` with a typographic apostrophe, the Swift string
uses `we'll`. This is the sentence that makes the confirmation a precondition, and it is the
reason the sheet exists.

### `initiativeconfirm` — the affirmative button

> I confirm I am **requesting this service** on my own exclusive initiative

INT's button reads *"I confirm I am **accessing this website** on my own exclusive
initiative"*. **This is the most substantive departure in the change and the one most worth a
reviewer's attention.**

The rewrite is deliberate and, we think, in the right direction. §2.5 asks the customer to
confirm that *"your **request** is made solely on your own exclusive initiative"* — a request
for a service, not a visit to a page. The website's button says the weaker of the two things
because on the website that is all that is happening. At this point in the app the customer is
submitting an IBAN and an email to have Bittr register them; "accessing this website" would be
plainly untrue, and a confirmation the customer can see is untrue is worth less than no
confirmation at all.

## What was deliberately not carried over

- **INT's opening paragraph** — *"You are about to enter the Bittr AG website, and it appears
  your IP address is located outside of Switzerland…"*. Every clause of it is a geo-IP result.
  The app performs no IP lookup and BIT-50 item 4 rules one out of scope.
- **INT's acknowledgement sentence** — *"By clicking … you acknowledge that you have read,
  understood, and accepted the aforementioned information. Furthermore, you affirm that you
  are accessing this site by your own volition without any active promotion or solicitation
  on the part of Bittr AG."*

  **Raised, not decided.** The first half is self-evident from tapping the button. The second
  half is not: it is a distinct affirmation — *no active promotion or solicitation on Bittr's
  part* — and §2.3 of the Terms carries its own version (*"You also confirm that Bittr did and
  does not solicit you as a Customer and that you initiated any contact with Bittr
  unassisted."*). The button title as written covers the customer's own initiative but not the
  affirmation that Bittr did not solicit them. Whether that gap matters is a question for the
  Compliance & Regulatory Officer; the implementation is one string away either way.

## Where the copy is shown

One sheet, `Transfer1ViewController` — the IBAN + email screen of Bittr signup. It is
presented when the customer taps **Verify** with both fields filled, *before* the
IBAN/email call reaches Bittr, at `Transfer1ViewController.swift:147` →
`confirmInitiativeThenGatherIbanDetails():174`.

That tap is the first moment Bittr does anything for this customer: it validates their IBAN
and emails them a code. §2.5 conditions *providing any Services*, so the confirmation is
collected before that call rather than at app launch — opening a non-custodial wallet is not
Bittr providing the purchase service (BIT-27 `perimeter` § 2).

The sheet has **no close cross** (`AlertManager.swift:381+`). The only ways out are the
confirm button and Cancel, so nothing the customer does by accident can be recorded as a
confirmation they did not give.

Asked **once per registration**, not once per tap: `recordedInitiativeConfirmation:157` reads
back a confirmation already stored against the IBAN entity, so a customer correcting a typo in
their email is not asked again. Asking twice for one registration is noise, not consent.

## What is recorded

- `IbanEntity.initiativeConfirmedAt` (`IbanEntity.swift:34`) — ISO-8601, UTC, second
  precision. UTC so the stored moment is unambiguous wherever the customer was.
- Persisted locally through `CacheManager.setInitiativeConfirmedAt` (`CacheManager.swift:129`).
- Sent to the backend as **`exclusive_initiative_confirmed_at`** on the `POST /api/customer`
  registration call (`Transfer2ViewController.swift:377`), so the confirmation is held against
  the customer record and not only in one device's cache.

Sent **only when present**. A registration made before the app collected this has nothing to
send, and an absent field is the honest representation of that — an empty string or a
back-filled timestamp would be a record of a confirmation that never happened.

**The backend field is not yet agreed.** Whether `exclusive_initiative_confirmed_at` is stored
or silently dropped is BIT-28's question. Until that lands, the app's own cache is the only
record.
