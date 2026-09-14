#!/usr/bin/env python3
"""Enforce the perimeter's store-listing constraints on Play Store copy.

Reads every *.txt in a listing locale directory (app_name, short_description,
full_description, release_notes, feature_graphic) and fails on anything the
perimeter rule forbids in a **worldwide wallet listing** (`perimeter` v1.1 §6,
restated as BIT-51 items 1-7):

  - the service sold to the reader — buy/sell/exchange vocabulary   (item 1)
  - fiat amounts and currency symbols of any kind                   (item 2)
  - EUR, SEPA, or the name of any EU/EEA country                    (item 2)
  - a named regulatory status — VQF, SRO, supervised, licence       (item 1)
  - country availability described as a safeguard                   (item 7)
  - custody/registration claims that are Tier 1 copy                (perimeter §7.6)

It also warns (does not fail) on the Tier 2 vocabulary — regulated, licensed,
compliant, safe, secure, guaranteed — which is allowed but has to be seen.

Usage:
    check_listing.py [LOCALE_DIR]      # defaults to ./en-GB
    check_listing.py --control         # run against ./control, expect failures

Exit code 0 = clean, 1 = at least one hard violation. Under --control the
codes invert: 0 means the checker correctly rejected the bad control.

### Why these rules, and why they got stricter rather than looser

The country decision went from Switzerland-only to worldwide (Ruben,
2026-09-10, `perimeter` v1.1 §6). That decision rests on the premise "this is a
non-custodial bitcoin wallet". The listing therefore has to be the thing the
decision was made about: if the store page sells Bittr's purchase service to a
reader in Germany, the basis no longer describes what was published. So the
EU-country and currency rules below are *not* leftovers from the Swiss-only
brief — they are load-bearing under worldwide distribution, and the service
vocabulary rule is new because of it.

### What this checker cannot see

Word lists catch copy that *names* the service. They do not catch copy that
describes a capability only the service delivers. That is `check_fidelity.py`'s
job — it binds every claim in the listing to the parity rows that have to read
`done` on Android before the claim may be published.
"""

import pathlib
import re
import sys

# --- Hard failures -----------------------------------------------------------

CURRENCY_SYMBOLS = "€$£¥₣₤₽₹₺₴₦₩฿"

EU_EEA_COUNTRIES = [
    # EU 27
    "Austria", "Belgium", "Bulgaria", "Croatia", "Cyprus", "Czechia",
    "Czech Republic", "Denmark", "Estonia", "Finland", "France", "Germany",
    "Greece", "Hungary", "Ireland", "Italy", "Latvia", "Lithuania",
    "Luxembourg", "Malta", "Netherlands", "Poland", "Portugal", "Romania",
    "Slovakia", "Slovenia", "Spain", "Sweden",
    # EEA additions
    "Iceland", "Liechtenstein", "Norway",
]

CURRENCY_WORDS = [
    "EUR", "CHF", "USD", "GBP", "SEK", "NOK", "DKK", "PLN", "CZK", "HUF",
    "euro", "euros", "franc", "francs", "dollar", "dollars", "pound",
    "pounds", "krona", "kronor", "krone", "zloty",
]

HARD_RULES = [
    (
        # BIT-51 item 1. The listing describes the wallet; buying bitcoin from
        # Bittr AG is the service, and the service is offered in Switzerland
        # only. Note the approved copy passes this rule with nothing removed —
        # that is the check that the rule is sized right rather than merely
        # strict.
        "service offered to the reader",
        re.compile(
            r"\b(buy|buys|buying|bought|purchase|purchases|purchasing|"
            r"sell|sells|selling|sold|exchange|exchanges|exchanging|"
            r"trade|trades|trading|invest|investing|investment|"
            r"top[- ]?up|top[- ]?ups|deposit|deposits|withdraw|withdrawal|"
            r"savings plan|recurring (?:purchase|buy|order|payment)|DCA)\b",
            re.IGNORECASE,
        ),
    ),
    (
        "currency symbol",
        re.compile(f"[{re.escape(CURRENCY_SYMBOLS)}]"),
    ),
    (
        "currency word or code",
        re.compile(r"\b(" + "|".join(CURRENCY_WORDS) + r")\b", re.IGNORECASE),
    ),
    (
        "fiat amount",
        # 999.99 / 1,000 / 100.- — a decimal or grouped number, which in a
        # listing is only ever a price or a limit. Plain small integers are
        # fine ("one wallet", "24 words").
        re.compile(r"\b\d{1,3}(?:[.,]\d{3})+\b|\b\d+[.,]\d{2}\b|\b\d+\.-"),
    ),
    (
        "EU / EEA reference",
        re.compile(
            r"\b(EU|EEA|European Union|European Economic Area|Europe|European)\b"
        ),
    ),
    (
        "EU / EEA country named",
        re.compile(r"\b(" + "|".join(EU_EEA_COUNTRIES) + r")\b"),
    ),
    (
        "payment rail named",
        re.compile(r"\b(SEPA|IBAN|SWIFT|BIC)\b"),
    ),
    (
        # BIT-51 item 1 / Tier 1 item 9. The VQF clause was in the first draft,
        # lifted verbatim from Bittr's own Terms, and Compliance deleted it: in
        # the Terms it sits inside a paragraph that explains what SRO
        # affiliation means, and in a worldwide listing it sits next to a Swiss
        # address and reads as *supervised* to a reader in a country where
        # Bittr AG has no status at all. Hard rule so it cannot come back
        # quietly in an edit six months from now.
        "regulatory status named",
        re.compile(
            r"\b(VQF|FINMA|SRO|self[- ]regulat\w*|supervis\w*|"
            r"authoris(?:ed|ation) by|authoriz(?:ed|ation) by)\b",
            re.IGNORECASE,
        ),
    ),
    (
        # BIT-51 item 7. Play country availability keys off the user's Play
        # account country — not residence, not IP, not IBAN country — and does
        # not stop sideloading. It has never been an access control, so the
        # listing must not present it as one.
        "country availability described as a safeguard",
        re.compile(
            r"\b(only available in|available only in|not available in|"
            r"restricted to|limited to (?:customers|users|residents)|"
            r"residents? of|geo[- ]?blocked|country availability|"
            r"only for (?:customers|users|residents))\b",
            re.IGNORECASE,
        ),
    ),
    (
        "Tier 1 prohibited claim",
        re.compile(
            r"\bno[ -]KYC\b|\banonymous(ly)?\b|\bno registration\b|"
            r"\bno sign[ -]?up\b|\buntraceable\b",
            re.IGNORECASE,
        ),
    ),
]

# --- Warnings ----------------------------------------------------------------

SOFT_RULES = [
    (
        "Tier 2 vocabulary (allowed, but must be reviewed)",
        re.compile(
            r"\b(regulated|licen[cs]ed|compliant|compliance|safe|safely|"
            r"secure|securely|guaranteed|guarantee|insured|risk[- ]free)\b",
            re.IGNORECASE,
        ),
    ),
]

# --- Play Console field limits ----------------------------------------------

LIMITS = {
    "app_name": 30,
    "short_description": 80,
    "full_description": 4000,
    "release_notes": 500,
}


def check(directory: pathlib.Path) -> tuple[int, int, int]:
    """Return (files checked, hard violations, warnings) for one locale dir."""
    files = sorted(directory.glob("*.txt"))
    if not files:
        print(f"no listing .txt files found in {directory}", file=sys.stderr)
        return (0, 1, 0)

    hard = 0
    soft = 0

    for path in files:
        text = path.read_text(encoding="utf-8")
        stem = path.stem

        limit = LIMITS.get(stem)
        if limit is not None:
            # Play counts the field as submitted; the trailing newline here is a
            # file artefact, not part of the field.
            length = len(text.rstrip("\n"))
            status = "ok" if length <= limit else "OVER"
            print(f"{stem}: {length}/{limit} chars [{status}]")
            if length > limit:
                hard += 1

        for label, pattern in HARD_RULES:
            for m in pattern.finditer(text):
                line = text.count("\n", 0, m.start()) + 1
                print(f"FAIL {path.name}:{line}: {label} — {m.group(0)!r}")
                hard += 1

        for label, pattern in SOFT_RULES:
            for m in pattern.finditer(text):
                line = text.count("\n", 0, m.start()) + 1
                print(f"WARN {path.name}:{line}: {label} — {m.group(0)!r}")
                soft += 1

    return (len(files), hard, soft)


def main() -> int:
    here = pathlib.Path(__file__).resolve().parent
    args = sys.argv[1:]

    # A green run means nothing unless the checker is known to bite. --control
    # runs it against copy written to trip every rule; a clean control is a
    # broken checker, not clean copy.
    if args[:1] == ["--control"]:
        _, hard, _ = check(here / "control")
        print()
        if hard:
            print(f"control: {hard} violations — checker bites, as intended")
            return 0
        print("control: 0 violations — THE CHECKER IS BROKEN", file=sys.stderr)
        return 1

    target = here / (args[0] if args else "en-GB")
    files, hard, soft = check(target)
    print()
    print(f"{files} files checked · {hard} violations · {soft} warnings")
    return 1 if hard else 0


if __name__ == "__main__":
    sys.exit(main())
