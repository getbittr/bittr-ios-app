# Exclusive-initiative confirmation — copy sources

The strings at `ios/bittr/Language.swift:172-174` are not authored. They are assembled from
two documents Bittr already publishes. This file records which sentence came from where, and
every place the app's wording departs from the source — so a reviewer can check the copy
without re-reading the live site, and so a later edit knows what it is allowed to touch.

**Do not reword any of these strings without the Compliance & Regulatory Officer.** It is a
Tier 1 trigger on BIT-27. This file is the thing to bring to that conversation.

**All three strings are signed off** by the Compliance & Regulatory Officer on
**2026-09-11** (BIT-65, summarised on BIT-50). The review changed one of them —
`initiativeconfirm` — and confirmed the other two as they stood. The sections below record
what was decided, not what is still open.

## Sources

Both fetched from production on **2026-09-11**. Both are subject to change without anyone
telling us; re-fetch before relying on this file.

| Ref | Source |
|-----|--------|
| **§2.5** | `getbittr.com/terms-and-conditions` § 2.5 *Important provisions for EU residents*. Terms version **1.1 – 28 December 2024**. |
| **INT** | The geo-IP interstitial rendered on every `getbittr.com` page, under the headings *Notification for non-Swiss users* / *Regulatory Information*. |

## The three strings

### `initiativetitle` — alert heading

> Your own exclusive initiative

**This is the one string with no source.** Neither INT heading works in the app: *"Notification
for non-Swiss users"* presumes a geo-IP result the app does not have and must not acquire
(out of scope, BIT-50 item 4), and *"Regulatory Information"* describes the middle paragraph
rather than the thing being asked of the customer. The phrase used is lifted from §2.5's own
words but the heading itself is ours.

**Decided: the authored heading stays.** This was put to the Compliance & Regulatory Officer
with **"Regulatory Information"** offered as the drop-in that needs no judgement, and the
authored heading was kept deliberately — it names the thing being asked of the customer,
which the INT heading does not. Do not swap in "Regulatory Information".

### `initiativemessage` — alert body, three paragraphs

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

`IMPORTANT NOTE:` dropped — it is typography for a wall of text on a web page, and the alert
is already three paragraphs long. The sentence itself is unchanged.

**Paragraph 3 — from §2.5, verbatim.**

> Before we can provide any Services to you, we'll need you to confirm that your request is
> made solely on your own exclusive initiative, without any encouragement or solicitation
> from us.

Word for word, including `Services` capitalised as the Terms define it. The only difference
is the apostrophe: the site renders `we’ll` with a typographic apostrophe, the Swift string
uses `we'll`. This is the sentence that makes the confirmation a precondition, and it is the
reason the alert exists.

### `initiativeconfirm` — the affirmative button

> I confirm my request is made solely on my own exclusive initiative, without any
> encouragement or solicitation from Bittr

**From §2.5, verbatim apart from two substitutions forced by the first person:** `your` → `my`,
`from us` → `from Bittr`. The source clause is the one quoted as paragraph 3 of the alert body
— *"your request is made solely on your own exclusive initiative, without any encouragement or
solicitation from us"*.

This is not INT's button. INT reads *"I confirm I am **accessing this website** on my own
exclusive initiative"*, and an earlier draft of this change shipped the halfway rewrite
*"I confirm I am **requesting this service** on my own exclusive initiative"*. Both were
superseded by the Compliance & Regulatory Officer's review, for two reasons:

- **"accessing this website" would be false in the app.** There is no website here; the
  customer is submitting an IBAN and an email to have Bittr register them. A confirmation the
  customer can see is untrue is worth less than no confirmation at all.
- **Both earlier strings confirmed only half of what the body asks.** The alert quotes §2.5
  asking the customer to confirm a two-part statement — own exclusive initiative **and** no
  encouragement or solicitation from Bittr. The button affirmed the first part and left the
  second unconfirmed. Quoting the operative clause whole closes that gap, which is why no
  fourth string was needed.

## What was deliberately not carried over

- **INT's opening paragraph** — *"You are about to enter the Bittr AG website, and it appears
  your IP address is located outside of Switzerland…"*. Every clause of it is a geo-IP result.
  The app performs no IP lookup and BIT-50 item 4 rules one out of scope.
- **INT's acknowledgement sentence** — *"By clicking … you acknowledge that you have read,
  understood, and accepted the aforementioned information. Furthermore, you affirm that you
  are accessing this site by your own volition without any active promotion or solicitation
  on the part of Bittr AG."*

  **Raised, and now answered — by the button, not by a fourth string.** The first half is
  self-evident from tapping the button. The second half is a distinct affirmation — *no active
  promotion or solicitation on Bittr's part* — which §2.3 of the Terms carries its own version
  of (*"You also confirm that Bittr did and does not solicit you as a Customer and that you
  initiated any contact with Bittr unassisted."*). The earlier button title covered the
  customer's own initiative but not that. The signed-off `initiativeconfirm` quotes §2.5's
  operative clause whole — *"without any encouragement or solicitation from Bittr"* — so the
  affirmation is made in the customer's own words, on the control they tap. Nothing further is
  carried over from INT's acknowledgement sentence.

## Where the copy is shown

One alert, on `Transfer1ViewController` — the IBAN + email screen of Bittr signup, which the Buy
flow's registration reuses. It goes up when the customer taps **Verify** with both fields
filled, *before* the IBAN/email call reaches Bittr: `nextButtonTapped:139` →
`confirmInitiative(then:):169`, an ordinary `showAlert` with Cancel and Confirm.

That tap is the first moment Bittr does anything for this customer: it validates their IBAN
and emails them a code. §2.5 conditions *providing any Services*, so the confirmation is
collected before that call rather than at app launch — opening a non-custodial wallet is not
Bittr providing the purchase service (BIT-27 `perimeter` § 2).

On Android the same alert comes from `BuyController.confirmInitiative`, drawn by
`BittrInlineAlert` in the screen's own window, with the same strings and button order.

## How the alert can be dismissed

A confirmation is only worth something if it cannot be skipped. Every way the alert goes away,
other than **Confirm**, records nothing and sends nothing — each was checked against the code
rather than assumed:

- **Cancel and the close cross.** Cancel is a `.dismiss` button, so `showAlert` also shows the
  cross (`isDismissable`, `AlertManager.swift:270`), and the cross does what Cancel does:
  `hideAlert()`. Only Confirm's handler writes `initiativeConfirmedAt` and calls `proceed()`.
  On Android the X and Back both run Cancel's action.
- **Tapping outside the card does nothing.** The overlay is a full-screen view pinned to the
  host's edges (`makeAlertChrome:98`), with no gesture recognizer and no `hitTest` or
  `point(inside:)` override. Touches outside the card stop there — they neither dismiss it nor
  reach the screen underneath. On Android the dim swallows them the same way.
- **There is no back gesture on iOS.** The app has no `UINavigationController` at all, so no
  interactive pop exists on any screen, this one included.
- **The screen underneath is covered.** `alertHost:56` walks up to the topmost parent before
  adding the overlay, so in Bittr signup it covers `CoreViewController` — the whole app — and in
  the Buy flow it covers the presented registration controller entirely.

**One more way out on iOS, and it is safe.** In the Buy flow, `RegisterIbanViewController`
arrives through a `show` segue with no navigation controller (`Main.storyboard:2521`), so UIKit
presents it as a `pageSheet`, and `isModalInPresentation` is never set. The customer can pull
the whole registration flow down while the alert is up. That abandons registration: no
timestamp is written and no customer is registered. It is Cancel by another gesture, not a way
past the gate. Left as is deliberately — making the flow undismissable would trap the customer,
and the property that matters is that nothing but Confirm records a confirmation.

**The confirm button renders unclipped at any length.** Its title is far too long to sit beside
Cancel, so the two buttons stack, Confirm above Cancel. `makeAlertButton:169` gives the label
`numberOfLines = 0`, and the button only a minimum height of 40, so the plate grows to the text
instead of cutting it.

**The Maestro flows do not depend on the wording.** All three flows
(`shared/flows/onboarding/happy_path_signup.yaml`, `features/buy_signup.yaml`,
`features/buy_signup_no_notifications.yaml`) tap Confirm as `alert.button.1` and Cancel as
`alert.button.0`, never by text, so the copy can be revised without touching a test.

Asked **once per registration**, not once per tap: `recordedInitiativeConfirmation:158` reads
back a confirmation already stored against the IBAN entity, so a customer correcting a typo in
their email is not asked again. Asking twice for one registration is noise, not consent.

## What is recorded

- `IbanEntity.initiativeConfirmedAt` (`IbanEntity.swift:25`) — ISO-8601, UTC, second
  precision. UTC so the stored moment is unambiguous wherever the customer was.
- Persisted locally with the IBAN entity, through `CacheManager.addIban` (`CacheManager.swift:113`).
- Sent to the backend as **`exclusive_initiative_confirmed_at`** on the `POST /api/customer`
  registration call (`Transfer2ViewController.swift:374`), so the confirmation is held against
  the customer record and not only in one device's cache.

Sent **only when present**. A registration made before the app collected this has nothing to
send, and an absent field is the honest representation of that — an empty string or a
back-filled timestamp would be a record of a confirmation that never happened.

**The backend field is not yet agreed.** The backend today drops
`exclusive_initiative_confirmed_at` — that is **BIT-84**, blocked on BIT-31. Until it lands,
the app's own cache is the only record. (An earlier version of this file, and BIT-50 item 3,
pointed at BIT-28 for this; that pointer was wrong — BIT-28 is Android support readiness.)

**Android asks with the same alert and the same strings** (BIT-85).
