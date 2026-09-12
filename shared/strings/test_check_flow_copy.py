#!/usr/bin/env python3
"""Prove check_flow_copy.py fails on the things it exists to catch.

A guard nobody has seen fail is a guard nobody should trust, and this one is
about to be the only thing standing between the `*Language.swift` ->
`shared/strings/` move and 24 flows that assert on copy. So each case builds a
throwaway copy of the repo's real inputs, breaks one thing the way the migration
could plausibly break it, and asserts the check goes red and says why.

The last two cases are the migration itself: the same lock file, re-checked
against an `en.json` generated from the Swift table. Verbatim passes; one
reworded value fails. That is the property the consolidation has to hold, tested
without a simulator.

    ./shared/strings/test_check_flow_copy.py
"""

import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
CHECK = "shared/strings/check_flow_copy.py"
SWIFT = "ios/bittr/Language.swift"
LOCK = "shared/strings/copy-lock.json"
# Locked copy with exactly one key and no `literals`, so a mutation of it has a
# single unambiguous expected failure.
SIMPLE = ("Invoice and amount", "invoiceandamount", "Invoice and amount")


def build() -> Path:
    """A temp tree holding just the files the check reads."""
    tmp = Path(tempfile.mkdtemp(prefix="copylock-"))
    for rel in (CHECK, SWIFT, LOCK):
        (tmp / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / rel, tmp / rel)
    shutil.copytree(ROOT / "shared/flows", tmp / "shared/flows")
    # Files named by `literals` entries, so the literal checks have something to read.
    for entry in json.loads((ROOT / LOCK).read_text())["matchers"]:
        for literal in entry.get("literals", []):
            dest = tmp / literal["file"]
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / literal["file"], dest)
    return tmp


def run(tmp: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, CHECK, *args], cwd=tmp, capture_output=True, text=True
    )


def swift_to_json(tmp: Path) -> dict[str, str]:
    """The allWords table as the flat locale JSON the consolidation will produce."""
    sys.dont_write_bytecode = True  # no __pycache__ next to the script it imports
    sys.path.insert(0, str(ROOT / "shared/strings"))
    import check_flow_copy

    return check_flow_copy.load_copy(tmp / SWIFT)


CASES = []


def case(name):
    def register(fn):
        CASES.append((name, fn))
        return fn

    return register


@case("unmodified inputs pass")
def _(tmp):
    result = run(tmp)
    assert result.returncode == 0, result.stdout
    assert "0 failures" in result.stdout


@case("a reworded key is reported as drift, naming the flow")
def _(tmp):
    matcher, key, text = SIMPLE
    path = tmp / SWIFT
    path.write_text(path.read_text().replace(f'"{key}": "{text}"', f'"{key}": "Invoice & amount"'))
    result = run(tmp)
    assert result.returncode == 1, result.stdout
    assert f"drift: {key}" in result.stdout, result.stdout
    assert "receive_invoice.yaml" in result.stdout, result.stdout


@case("copy that grew a suffix is reported — Maestro full-matches, so it would break")
def _(tmp):
    # The case a substring search would miss. `text: "Cancel"` stops selecting a
    # button reading "Cancel payment", because Maestro matches the regex against
    # the element's entire text. A guard more permissive than the tool it guards
    # goes quiet on precisely the rewording it exists to catch.
    path = tmp / SWIFT
    path.write_text(path.read_text().replace('"cancel": "Cancel"', '"cancel": "Cancel payment"'))
    result = run(tmp)
    assert result.returncode == 1, "a suffix-extended string passed as unchanged:\n" + result.stdout
    assert "drift: cancel" in result.stdout, result.stdout
    assert "settings.yaml" in result.stdout, result.stdout


@case("an entry pre-locked ahead of its flow is stale, not a failure")
def _(tmp):
    # BIT-10's receive_lnurl.yaml is locked before it has merged, so the merge is
    # not a red build. Stale entries must stay advisory or that trick stops working.
    lock = json.loads((tmp / LOCK).read_text())
    assert any(e["matcher"] == "Unavailable" for e in lock["matchers"]), "pre-lock entry gone"
    result = run(tmp)
    assert result.returncode == 0, result.stdout
    assert "stale: 'Unavailable'" in result.stdout, result.stdout


@case("a deleted key is reported as missing, with the text it used to have")
def _(tmp):
    matcher, key, text = SIMPLE
    path = tmp / SWIFT
    path.write_text(re.sub(rf'^\s*"{key}".*\n', "", path.read_text(), flags=re.M))
    result = run(tmp)
    assert result.returncode == 1, result.stdout
    assert f"missing key: {key}" in result.stdout, result.stdout
    assert repr(text) in result.stdout, result.stdout


@case("a renamed hardcoded literal is reported, not silently skipped")
def _(tmp):
    # The QR long-press menu's "Copy" is a UIAction title, outside allWords — the
    # exact shape of copy a consolidation of allWords alone would leave behind.
    path = tmp / "ios/bittr/Move, Send, Receive/ReceiveVC/ReceiveViewController.swift"
    path.write_text(path.read_text().replace('UIAction(title: "Copy"', 'UIAction(title: "Copy address"'))
    result = run(tmp)
    assert result.returncode == 1, result.stdout
    assert "literal gone: 'Copy'" in result.stdout, result.stdout
    assert "receive_onchain.yaml" in result.stdout, result.stdout


@case("a new matcher no one classified is reported as undeclared")
def _(tmp):
    path = tmp / "shared/flows/features/settings.yaml"
    path.write_text(path.read_text() + '\n- assertVisible:\n    text: "Some brand new alert"\n')
    result = run(tmp)
    assert result.returncode == 1, result.stdout
    assert "undeclared: 'Some brand new alert'" in result.stdout, result.stdout


@case("a matcher in a comment is not mistaken for a live one")
def _(tmp):
    path = tmp / "shared/flows/features/settings.yaml"
    path.write_text(path.read_text() + '\n# the alert asserts text: "Some brand new alert"\n')
    result = run(tmp)
    assert result.returncode == 0, result.stdout


@case("--update cannot launder a drift into the lock")
def _(tmp):
    matcher, key, text = SIMPLE
    path = tmp / SWIFT
    path.write_text(path.read_text().replace(f'"{key}": "{text}"', f'"{key}": "Invoice & amount"'))
    run(tmp, "--update")
    result = run(tmp)
    assert result.returncode == 1, "a regeneration silently accepted the rewording:\n" + result.stdout
    assert f"drift: {key}" in result.stdout, result.stdout


@case("the same lock passes against a verbatim en.json — the migration, done right")
def _(tmp):
    (tmp / "shared/strings/en.json").write_text(json.dumps(swift_to_json(tmp), indent=2, ensure_ascii=False))
    (tmp / SWIFT).unlink()  # the whole point: the Swift table is gone
    result = run(tmp)
    assert result.returncode == 0, result.stdout
    assert "shared/strings/en.json" in result.stdout, result.stdout


@case("the same lock fails against an en.json with one word changed — the migration, done wrong")
def _(tmp):
    matcher, key, text = SIMPLE
    table = swift_to_json(tmp)
    table[key] = "Invoice & amount"
    (tmp / "shared/strings/en.json").write_text(json.dumps(table, indent=2, ensure_ascii=False))
    (tmp / SWIFT).unlink()
    result = run(tmp)
    assert result.returncode == 1, (
        "a rewording survived the move to en.json undetected — this is exactly the "
        "failure BIT-12 exists to prevent:\n" + result.stdout
    )
    assert f"drift: {key}" in result.stdout, result.stdout
    assert "receive_invoice.yaml" in result.stdout, result.stdout


@case("a half-migrated tree passes — the moved key resolves from en.json, the rest from Swift")
def _(tmp):
    # The move is a key at a time, not one commit. BIT-56 landed a two-key en.json
    # beside a full Language.swift on `ios-parity`, and the guard — which preferred
    # en.json the moment it existed — called 10 keys that had never moved deleted.
    matcher, key, text = SIMPLE
    path = tmp / SWIFT
    path.write_text(path.read_text().replace(f'"{key}": "{text}"', f'"{key}moved": "{text}"'))
    (tmp / "shared/strings/en.json").write_text(json.dumps({key: text}, indent=2, ensure_ascii=False))
    result = run(tmp)
    assert result.returncode == 0, (
        "a key that moved to en.json while the rest stayed in Language.swift read as "
        "missing — a half-migrated tree is a red build for no reason:\n" + result.stdout
    )
    assert "0 failures" in result.stdout, result.stdout


@case("a key reworded on its way into a half-migrated en.json still fails")
def _(tmp):
    # What the overlay order buys: en.json wins over Language.swift, so the copy of
    # the key left behind in the Swift table cannot mask the rewording. Get this
    # backwards and the union silently un-arms the guard for every key mid-move.
    matcher, key, text = SIMPLE
    (tmp / "shared/strings/en.json").write_text(
        json.dumps({key: "Invoice & amount"}, indent=2, ensure_ascii=False)
    )
    result = run(tmp)
    assert result.returncode == 1, (
        "en.json reworded the key and Language.swift's stale copy masked it:\n" + result.stdout
    )
    assert f"drift: {key}" in result.stdout, result.stdout
    assert "receive_invoice.yaml" in result.stdout, result.stdout


def main() -> int:
    failed = 0
    for name, fn in CASES:
        tmp = build()
        try:
            fn(tmp)
            print(f"pass  {name}")
        except AssertionError as error:
            failed += 1
            print(f"FAIL  {name}\n      {error}")
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    print(f"\n{len(CASES) - failed}/{len(CASES)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
