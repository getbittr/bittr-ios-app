#!/usr/bin/env python3
"""Generate platform test ID constants from test-ids.json.

Reads:
  shared/test-ids/test-ids.json — hierarchical, leaves are null.

Writes:
  ios/bittr/Helpers/TestIDs.swift — Swift nested enum constants.
  android/app/src/main/java/com/bittr/generated/TestIDs.kt — when android/ scaffold lands.

The full ID for a leaf is the dot-joined path from the root, matching across platforms so Maestro flows see identical strings on iOS and Android.
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
JSON_PATH = ROOT / "shared/test-ids/test-ids.json"
SWIFT_PATH = ROOT / "ios/bittr/Helpers/TestIDs.swift"


def to_pascal(s: str) -> str:
    return s[0].upper() + s[1:] if s else s


def emit_swift(node: dict, path: list[str], indent: int) -> list[str]:
    pad = "    " * indent
    lines: list[str] = []
    for key in sorted(node.keys()):
        if key.startswith("_"):
            continue
        value = node[key]
        full = path + [key]
        if isinstance(value, dict):
            lines.append(f"{pad}enum {to_pascal(key)} {{")
            lines.extend(emit_swift(value, full, indent + 1))
            lines.append(f"{pad}}}")
        else:
            lines.append(f'{pad}static let {key} = "{".".join(full)}"')
    return lines


def main() -> int:
    if not JSON_PATH.exists():
        print(f"error: {JSON_PATH} not found", file=sys.stderr)
        return 1
    data = json.loads(JSON_PATH.read_text())

    swift = [
        "// AUTO-GENERATED. DO NOT EDIT.",
        "// Source: shared/test-ids/test-ids.json",
        "// Regenerate: ./shared/test-ids/build.py",
        "",
        "enum TestID {",
        *emit_swift(data, [], 1),
        "}",
        "",
    ]

    SWIFT_PATH.parent.mkdir(parents=True, exist_ok=True)
    SWIFT_PATH.write_text("\n".join(swift))
    print(f"wrote {SWIFT_PATH.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
