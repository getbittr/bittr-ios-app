#!/usr/bin/env bash
#
# Every `script:` input in .github/workflows/** must be POSIX sh.
#
# WHY THIS EXISTS
#
# reactivecircus/android-emulator-runner takes the commands to run on the booted
# emulator as a `script:` input, and runs them with /usr/bin/sh — dash on the
# Ubuntu runner images. Ours opened with `set -euo pipefail`, and the first CI run
# this workflow ever had died on that line:
#
#   /usr/bin/sh: 1: set: Illegal option -o pipefail
#   Error: The process '/usr/bin/sh' failed with exit code 2
#
# Two things make this worth a dedicated check rather than a fixed line.
#
# It is invisible to everything upstream of it. actionlint runs shellcheck over
# every `run:` block, which is why the rest of this workflow is covered — but
# `script:` is an input to a third-party action, so to actionlint it is an opaque
# string. Nothing in the repo could see inside it.
#
# And it fails at the worst possible moment: after the AVD has been created and
# the emulator has booted. The cheapest bug in the file to write, and one of the
# most expensive to find out about, roughly twenty minutes per attempt.
#
# It is also not reproducible everywhere, which is what makes a lint the right
# instrument. dash gained pipefail in 0.5.12, so on a current Ubuntu the exact
# failing line runs fine — a developer checking by hand on their own box gets a
# clean result and the runner still goes red. shellcheck's POSIX mode does not
# care what the local shell happens to support.
#
# WHAT IT CHECKS
#
#   1. Every `script:` value shellchecks clean as POSIX sh (SC3xxx = "this is a
#      bashism"). SC2xxx style findings are not this check's business.
#   2. Where a `script:` delegates with `bash <file>` — the fix we took, and the
#      one to prefer, since it puts the interpreter under our control — that file
#      must exist and shellcheck clean as bash.
#
# Runs in the build job, seconds in, long before an emulator is booted. Locally:
#   bash android/scripts/check-action-scripts.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "check-action-scripts: shellcheck not found." >&2
  echo "  Ubuntu/Debian: sudo apt-get install -y shellcheck   macOS: brew install shellcheck" >&2
  echo "  (GitHub-hosted runners have it preinstalled.)" >&2
  exit 127
fi

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

# Extraction is regex-based rather than PyYAML, to match shared/test-ids/*.py —
# these checks run on any python3 without a pip step, and a lint that needs
# installing is a lint someone skips.
python3 - "$workdir" <<'PY'
import re
import sys
from pathlib import Path

workdir = Path(sys.argv[1])
found = 0

for wf in sorted(Path(".github/workflows").glob("*.y*ml")):
    lines = wf.read_text().split("\n")
    i = 0
    while i < len(lines):
        # `script:` as a step input, block form or inline form.
        m = re.match(r"^(\s+)script:(\s*\|-?\s*|\s+\S.*)$", lines[i])
        if not m:
            i += 1
            continue
        indent, tail = m.group(1), m.group(2)
        start = i + 1  # 1-indexed line number of the `script:` key
        if tail.strip().startswith("|"):
            body, i = [], i + 1
            while i < len(lines):
                line = lines[i]
                if line.strip() == "":
                    body.append("")
                elif len(line) - len(line.lstrip()) > len(indent):
                    body.append(line)
                else:
                    break
                i += 1
            # Trim the trailing blank lines the block scan picks up.
            while body and body[-1] == "":
                body.pop()
            if not body:
                continue
            pad = min(len(l) - len(l.lstrip()) for l in body if l)
            text = "\n".join(l[pad:] if l else "" for l in body)
        else:
            text = tail.strip()
            i += 1

        found += 1
        out = workdir / f"script-{found}.sh"
        out.write_text(text + "\n")
        (workdir / f"script-{found}.origin").write_text(f"{wf}:{start}")

if found == 0:
    sys.exit("check-action-scripts: no `script:` inputs found in .github/workflows — "
             "this guard is now checking nothing. Delete it or fix the extractor.")
print(f"check-action-scripts: extracted {found} `script:` input(s).")
PY

failed=0

for script in "$workdir"/script-*.sh; do
  origin=$(cat "${script%.sh}.origin")

  # 1. The inline text must be POSIX. SC3xxx is exactly the "not portable to sh"
  #    family, and it is the only family this gate has an opinion about — SC2xxx
  #    is style, and a portability check that also fails on style gets disabled.
  #    There is no code-range filter, so the family is selected from the output
  #    instead; the exit status is deliberately ignored for the same reason.
  #    (A comment whose first word is the linter's own name reads as a directive
  #    and fails to parse — which is how this line came to be worded this way.)
  shellcheck -s sh -f gcc "$script" 2>&1 | grep -F '[SC3' > "$script.out" || true
  if [ -s "$script.out" ]; then
    failed=1
    echo "::error file=${origin%%:*},line=${origin##*:}::A \`script:\` input at $origin is not POSIX sh. The action runs it under /usr/bin/sh (dash), not bash, and it will fail AFTER the emulator has booted. Move the body to a file and call it with \`bash <file>\` — see android/scripts/ci-smoke.sh."
    echo "--- $origin"
    sed "s|$script|$origin|" "$script.out"
  fi

  # 2. If it delegates to a bash file, that file has to exist and be clean.
  while read -r target; do
    [ -n "$target" ] || continue
    if [ ! -f "$target" ]; then
      failed=1
      echo "::error::The \`script:\` at $origin runs \`bash $target\`, which does not exist. The job would fail after booting an emulator."
      continue
    fi
    if ! shellcheck -s bash "$target"; then
      failed=1
      echo "::error file=$target::$target is referenced by the \`script:\` at $origin and does not shellcheck clean."
    fi
  done < <(grep -oE '(^|[^[:alnum:]_-])bash[[:space:]]+([[:alnum:]._/-]+)' "$script" \
            | grep -oE '[[:alnum:]._/-]+$' || true)
done

if [ "$failed" -ne 0 ]; then
  echo
  echo "check-action-scripts: FAILED."
  exit 1
fi

echo "check-action-scripts: all \`script:\` inputs are POSIX sh, and every delegated bash file is clean."
