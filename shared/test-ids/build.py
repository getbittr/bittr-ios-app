#!/usr/bin/env python3
"""Generate platform test ID constants from test-ids.json.

Reads:
  shared/test-ids/test-ids.json — hierarchical, leaves are null.

Writes:
  ios/bittr/Helpers/TestIDs.swift — Swift nested enum constants.
  android/core/common/src/main/kotlin/com/bittr/android/core/common/TestIDs.kt — Kotlin nested object constants.

The full ID for a leaf is the dot-joined path from the root, matching across platforms so Maestro flows see identical strings on iOS and Android.

Some IDs are assigned at runtime with a row/position number appended — the
mnemonic word labels, the history table cells, the alert buttons. Those leaves
carry an `_index` spec instead of `null` and additionally generate an `…At()`
helper, so the number is produced by one shared rule rather than by
hand-interpolation that can drift between platforms. See README.md.
"""

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
JSON_PATH = ROOT / "shared/test-ids/test-ids.json"
SWIFT_PATH = ROOT / "ios/bittr/Helpers/TestIDs.swift"
KOTLIN_PATH = (
    ROOT / "android/core/common/src/main/kotlin/com/bittr/android/core/common/TestIDs.kt"
)
KOTLIN_PACKAGE = "com.bittr.android.core.common"

# Kotlin hard keywords cannot be used bare as identifiers. Leaf names come from
# test-ids.json, which is written for Maestro rather than for Kotlin, so escape
# rather than reject — a leaf called `object` or `is` is legal JSON and legal
# Swift, and should not fail the Android build.
KOTLIN_KEYWORDS = {
    "as", "break", "class", "continue", "do", "else", "false", "for", "fun", "if",
    "in", "interface", "is", "null", "object", "package", "return", "super",
    "this", "throw", "true", "try", "typealias", "typeof", "val", "var", "when",
    "while",
}


def kotlin_ident(name: str) -> str:
    return f"`{name}`" if name in KOTLIN_KEYWORDS else name


def to_pascal(s: str) -> str:
    return s[0].upper() + s[1:] if s else s


def index_spec(value) -> dict | None:
    """The `_index` spec of a runtime-indexed leaf, or None for a plain node."""
    if not isinstance(value, dict) or "_index" not in value:
        return None
    children = [k for k in value if not k.startswith("_")]
    if children:
        raise ValueError(f"_index leaf cannot also have children: {children}")
    spec = value["_index"] or {}
    return {"offset": spec.get("offset", 0), "separator": spec.get("separator", "")}


def emit_swift(node: dict, path: list[str], indent: int) -> list[str]:
    pad = "    " * indent
    lines: list[str] = []
    for key in sorted(node.keys()):
        if key.startswith("_"):
            continue
        value = node[key]
        full = path + [key]
        base = ".".join(full)
        spec = index_spec(value)
        if spec is not None:
            number = "position" if spec["offset"] == 0 else f"position + {spec['offset']}"
            lines.append(f"{pad}// Runtime-indexed: {index_comment(base, spec)}")
            lines.append(f'{pad}static let {key} = "{base}"')
            lines.append(
                f"{pad}static func {key}At(_ position: Int) -> String "
                f'{{ "{base}{spec["separator"]}\\({number})" }}'
            )
        elif isinstance(value, dict):
            lines.append(f"{pad}enum {to_pascal(key)} {{")
            lines.extend(emit_swift(value, full, indent + 1))
            lines.append(f"{pad}}}")
        else:
            lines.append(f'{pad}static let {key} = "{base}"')
    return lines


def index_comment(base: str, spec: dict) -> str:
    """`position 0 → "history.transactionButton0"` — the rule, spelled out."""
    first = f'{base}{spec["separator"]}{spec["offset"]}'
    second = f'{base}{spec["separator"]}{spec["offset"] + 1}'
    return f'position 0 → "{first}", position 1 → "{second}", …'


def emit_kotlin(node: dict, path: list[str], indent: int) -> list[str]:
    pad = "    " * indent
    lines: list[str] = []
    for key in sorted(node.keys()):
        if key.startswith("_"):
            continue
        value = node[key]
        full = path + [key]
        base = ".".join(full)
        spec = index_spec(value)
        if spec is not None:
            number = "$position" if spec["offset"] == 0 else f"${{position + {spec['offset']}}}"
            lines.append(f"{pad}// Runtime-indexed: {index_comment(base, spec)}")
            lines.append(f'{pad}const val {kotlin_ident(key)} = "{base}"')
            lines.append(
                f"{pad}fun {kotlin_ident(key + 'At')}(position: Int) = "
                f'"{base}{spec["separator"]}{number}"'
            )
        elif isinstance(value, dict):
            lines.append(f"{pad}object {to_pascal(key)} {{")
            lines.extend(emit_kotlin(value, full, indent + 1))
            lines.append(f"{pad}}}")
        else:
            lines.append(f'{pad}const val {kotlin_ident(key)} = "{base}"')
    return lines


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    # The Android port may not touch iOS sources without sign-off, so it must be
    # possible to regenerate one platform and leave the other file alone.
    parser.add_argument(
        "--platform",
        choices=("both", "ios", "android"),
        default="both",
        help="which platform file to write (default: both)",
    )
    args = parser.parse_args()

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

    if args.platform in ("both", "ios"):
        SWIFT_PATH.parent.mkdir(parents=True, exist_ok=True)
        SWIFT_PATH.write_text("\n".join(swift))
        print(f"wrote {SWIFT_PATH.relative_to(ROOT)}")

    kotlin = [
        "// AUTO-GENERATED. DO NOT EDIT.",
        "// Source: shared/test-ids/test-ids.json",
        "// Regenerate: ./shared/test-ids/build.py",
        "",
        f"package {KOTLIN_PACKAGE}",
        "",
        "/** Apply with `Modifier.testTag(TestID.Signup.Create.Start.createWalletButton)`. */",
        "object TestID {",
        *emit_kotlin(data, [], 1),
        "}",
        "",
    ]

    if args.platform in ("both", "android"):
        KOTLIN_PATH.parent.mkdir(parents=True, exist_ok=True)
        KOTLIN_PATH.write_text("\n".join(kotlin))
        print(f"wrote {KOTLIN_PATH.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
