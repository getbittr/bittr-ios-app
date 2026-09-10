#!/usr/bin/env python3
"""
screenshot_map.py — build the BIT-3 reference set index from the Maestro flows.

Emits, for every `takeScreenshot` step in shared/flows/**.yaml:

    screenshot file  ->  screen name  ->  producing flow + line + the steps
                                          that put the app on that screen

The map is derived from the flow YAML alone, so it is valid before the PNGs
exist: it is the *behavioural spec*. Once a capture lands, `--verify <dir>`
checks the real files against it (missing / orphaned / size consistency).

Usage:
    python3 screenshot_map.py --repo <repo-root> --out-dir <dir>
    python3 screenshot_map.py --repo <repo-root> --verify shared/docs/screenshots

Outputs (in --out-dir):
    reference-set.json   machine-readable index (one record per screenshot)
    reference-set.md     the human/design-facing document
"""

import argparse
import json
import os
import re
import sys
from collections import Counter, OrderedDict, defaultdict

# ── YAML-ish scanning ────────────────────────────────────────────────────────
# The flows are Maestro command lists: a config document, `---`, then a
# sequence of `- <command>` blocks. We scan lines rather than parsing YAML so
# every record keeps a real file:line anchor (and so this runs with no deps).

RE_SEP = re.compile(r"^---\s*$")
RE_TOP_ITEM = re.compile(r"^-\s+(.*)$")
RE_ANY_ITEM = re.compile(r"^(\s*)-\s+(.*)$")
RE_SCREENSHOT = re.compile(r"^\s*-?\s*takeScreenshot:\s*(\S+)\s*$")
RE_ID = re.compile(r"""^\s*id:\s*["']?([A-Za-z0-9_.\[\]-]+)["']?\s*$""")
RE_TEXT = re.compile(r"""^\s*text:\s*["']?(.+?)["']?\s*$""")
RE_RUNFLOW_INLINE = re.compile(r"^\s*-?\s*runFlow:\s*(\S+\.yaml)\s*$")
RE_RUNFLOW_FILE = re.compile(r"^\s*file:\s*(\S+\.yaml)\s*$")
RE_COMMAND = re.compile(r"^\s*-?\s*([a-zA-Z]+):")
RE_WHEN = re.compile(r"^\s*when:\s*$")

# Commands that describe user intent worth quoting as a "producing step".
INTERESTING = {
    "tapOn", "doubleTapOn", "longPressOn", "inputText", "eraseText",
    "swipe", "scroll", "scrollUntilVisible", "back", "launchApp",
    "assertVisible", "assertNotVisible", "extendedWaitUntil", "waitForAnimationToEnd",
    "runFlow", "runScript", "pressKey", "hideKeyboard", "openLink", "clearState",
    "inputRandomText", "copyTextFrom", "pasteText", "evalScript", "repeat",
}


def read_lines(path):
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read().splitlines()


def body_start(lines):
    """Index of the first command line (after the config `---` separator)."""
    for i, line in enumerate(lines):
        if RE_SEP.match(line):
            return i + 1
    return 0


def strip_comment(s):
    # Only strip a comment that follows whitespace, so `#` inside a value survives.
    return re.sub(r"\s+#.*$", "", s).strip()


class Step:
    """One command block in a flow, with its line span and the raw lines."""

    def __init__(self, index, line_no, indent, head, lines):
        self.index = index
        self.line_no = line_no          # 1-based
        self.indent = indent
        self.head = head                # e.g. 'tapOn:' or 'takeScreenshot: path'
        self.lines = lines              # raw block lines incl. head

    @property
    def command(self):
        m = RE_COMMAND.match(self.head)
        return m.group(1) if m else self.head.split(":")[0].strip()

    def ids(self):
        out = []
        for ln in self.lines:
            m = RE_ID.match(ln)
            if m:
                out.append(m.group(1))
        return out

    def texts(self):
        out = []
        for ln in self.lines:
            m = RE_TEXT.match(ln)
            if m:
                v = strip_comment(m.group(1)).strip("\"'")
                if v and not v.startswith("$"):
                    out.append(v)
        return out

    def subflows(self):
        out = []
        m = RE_RUNFLOW_INLINE.match(self.head)
        if m:
            out.append(m.group(1))
        for ln in self.lines:
            m = RE_RUNFLOW_FILE.match(ln)
            if m:
                out.append(m.group(1))
        return out

    def is_conditional(self):
        return any(RE_WHEN.match(ln) for ln in self.lines)

    def screenshots(self):
        """(dest, line_no) for every takeScreenshot in this block (incl. nested)."""
        out = []
        for off, ln in enumerate(self.lines):
            m = RE_SCREENSHOT.match(ln)
            if m:
                out.append((strip_comment(m.group(1)), self.line_no + off))
        return out

    def summary(self):
        """One-line human description of the step."""
        cmd = self.command
        ids = self.ids()
        txt = self.texts()
        target = ids[0] if ids else (txt[0] if txt else "")
        if cmd == "runFlow":
            subs = self.subflows()
            base = "runFlow " + (subs[0] if subs else "?")
            return base + (" (conditional)" if self.is_conditional() else "")
        if cmd == "runScript":
            script = ""
            for ln in self.lines:
                m = re.search(r"([\w./-]+\.js)", ln)
                if m:
                    script = os.path.basename(m.group(1))
                    break
            return "runScript " + script if script else "runScript"
        if target:
            return f"{cmd} {target}"
        return cmd


def parse_flow(path):
    """Split a flow file into top-level Step blocks."""
    lines = read_lines(path)
    start = body_start(lines)
    steps = []
    cur = None
    for i in range(start, len(lines)):
        raw = lines[i]
        if not raw.strip() or raw.strip().startswith("#"):
            if cur:
                cur.lines.append(raw)
            continue
        m = RE_TOP_ITEM.match(raw)
        if m:  # new top-level command
            cur = Step(len(steps), i + 1, 0, strip_comment(m.group(1)), [raw])
            steps.append(cur)
        elif cur is not None:
            cur.lines.append(raw)
    return steps


# ── Screen naming ────────────────────────────────────────────────────────────
# The accessibility-id namespace is the strongest screen signal the flows carry:
# `receive.addressTitle` -> the Receive screen. These map 1:1 onto the testTags
# the Android port will need, so we surface them as the screen key.

NAMESPACE_LABELS = {
    "home": "Home",
    "receive": "Receive",
    "send": "Send",
    "settings": "Settings",
    "unlock": "PIN unlock",
    "signup": "Signup / onboarding",
    "academy": "Academy",
    "map": "Bitcoin map",
    "value": "Bitcoin value",
    "swap": "Swap",
    "buy": "Buy / top-up",
    "pin": "PIN",
    "alert": "System alert",
    "transaction": "Transaction detail",
    "notification": "Notification",
}


def namespace_of(ids):
    """Dominant `foo.` namespace across a list of accessibility ids."""
    counts = defaultdict(int)
    for i in ids:
        if "." in i:
            counts[i.split(".")[0]] += 1
    if not counts:
        return None
    return max(counts.items(), key=lambda kv: (kv[1], kv[0]))[0]


def state_label(dest):
    """The state a shot captures, from its filename: `03b_share_sheet` -> 'Share sheet'."""
    label = re.sub(r"^\d+[a-z]?_", "", os.path.basename(dest)).replace("_", " ").strip()
    return label[:1].upper() + label[1:] if label else os.path.basename(dest)


def screen_of(dest, ns, anchor_texts):
    """
    The screen a shot belongs to — the unit a designer draws once.

    The accessibility-id namespace is the reliable signal. 14 of the shots are
    reached by text-only selectors (system alerts, the share sheet, toasts),
    which carry no id; for those we fall back to the screenshot's own directory
    and flag the shot as text-anchored so nobody mistakes it for an id-backed
    screen the port can assert on.
    """
    if ns:
        return NAMESPACE_LABELS.get(ns, ns.replace("_", " ").title()), False
    folder = os.path.basename(os.path.dirname(dest)).replace("_", " ").title()
    return (folder or "Unknown"), True


# ── Building the index ───────────────────────────────────────────────────────

# shared/flows/android/ is the Android harness (BIT-5), not an iOS flow — it
# targets com.bittr.android.regtest and must not appear in the iOS reference set.
EXCLUDED_DIRS = {"android"}


def collect_flows(flows_dir):
    out = []
    for root, dirs, files in os.walk(flows_dir):
        dirs[:] = [d for d in dirs if d not in EXCLUDED_DIRS]
        for f in sorted(files):
            if f.endswith(".yaml"):
                out.append(os.path.join(root, f))
    return sorted(out)


def load_registry(repo):
    """The canonical namespace -> id registry (shared/test-ids/test-ids.json)."""
    path = os.path.join(repo, "shared", "test-ids", "test-ids.json")
    if not os.path.exists(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return None
    # The registry is hierarchical to arbitrary depth; a leaf is `null` and its
    # id is the dot-joined path from the root (shared/test-ids/README.md).
    out = set()

    def walk(node, path):
        if isinstance(node, dict):
            for key, child in node.items():
                walk(child, f"{path}.{key}" if path else key)
        else:
            out.add(path)

    walk(data, "")
    return out


def load_screens_md(repo):
    """
    Parse the hand-written VC inventory (shared/docs/screens.md).

    It is the prose source of truth for what a screen *is*; this tool is the
    generated index of what the flows actually capture. Cross-checking the two
    is how we answer "does the suite screenshot every screen" without trusting
    either document on its own.
    """
    path = os.path.join(repo, "shared", "docs", "screens.md")
    if not os.path.exists(path):
        return None
    txt = open(path, "r", encoding="utf-8").read()
    screens = []
    for block in re.split(r"^### ", txt, flags=re.M)[1:]:
        name = block.split("\n", 1)[0].strip()
        # Skip the footnote and the `### <Screen name>` block in the Format section.
        if name.lower().startswith("footnote") or name.startswith("<"):
            continue
        shots = []
        m = re.search(r"^\s*-\s*\*\*Screenshots\*\*:\s*(.+)$", block, flags=re.M)
        if m:
            shots = re.findall(r"`([^`]+\.png)`", m.group(1))
        flows = []
        mf = re.search(r"^\s*-\s*\*\*Flow\*\*:\s*(.+)$", block, flags=re.M)
        if mf:
            flows = re.findall(r"`([^`]+)`", mf.group(1))
        screens.append({"name": name, "screenshots": shots, "flows": flows,
                        "declared": bool(m)})
    return screens


def reconcile_screens(screens, records):
    """screens.md rows whose declared screenshots no flow actually produces."""
    produced = {r["screenshot"] for r in records}
    # screens.md writes paths relative to shared/docs/screenshots/.
    produced_short = {p.split("shared/docs/screenshots/", 1)[-1] for p in produced}
    stale, ok = [], 0
    for s in screens:
        missing = [x for x in s["screenshots"]
                   if x.split("shared/docs/screenshots/", 1)[-1] not in produced_short]
        if missing:
            stale.append({"name": s["name"], "missing": missing,
                          "total": len(s["screenshots"])})
        elif s["screenshots"]:
            ok += 1
    return {"total": len(screens), "consistent": ok, "stale": stale,
            "undeclared": [s["name"] for s in screens if not s["screenshots"]]}


def git_pin(repo):
    """Commit + dirty state, so the map says which tree it was generated from."""
    import subprocess
    def run(*a):
        try:
            return subprocess.run(a, cwd=repo, capture_output=True, text=True,
                                  timeout=15).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            return ""
    return {
        "commit": run("git", "rev-parse", "--short", "HEAD"),
        "branch": run("git", "rev-parse", "--abbrev-ref", "HEAD"),
        "dirty": bool(run("git", "status", "--porcelain")),
    }


def suite_order(repo, flows_dir):
    """The runFlow sequence in suite.yaml, in order."""
    suite = os.path.join(flows_dir, "suite.yaml")
    if not os.path.exists(suite):
        return []
    order = []
    for ln in read_lines(suite):
        m = re.match(r"^\s*-\s*runFlow:\s*(\S+\.yaml)", ln)
        if m:
            order.append(m.group(1))
    return order


def build(repo):
    flows_dir = os.path.join(repo, "shared", "flows")
    records = []
    per_flow = OrderedDict()
    subflow_edges = defaultdict(set)   # flow -> set(subflow)

    for path in collect_flows(flows_dir):
        rel = os.path.relpath(path, repo)
        steps = parse_flow(path)
        flow_shots = []
        # Steps since the previous screenshot -> the ones that produced this screen.
        window = []
        for step in steps:
            for sub in step.subflows():
                resolved = os.path.normpath(os.path.join(os.path.dirname(path), sub))
                if os.path.exists(resolved):
                    subflow_edges[rel].add(os.path.relpath(resolved, repo))
            shots = step.screenshots()
            if not shots:
                window.append(step)
                continue
            for dest, line_no in shots:
                # Anchor ids: what this step and the immediately preceding
                # assertVisible steps prove is on screen.
                anchor_ids = list(step.ids())
                anchor_texts = []
                for prev in reversed(window):
                    if prev.command in ("assertVisible", "extendedWaitUntil", "repeat"):
                        anchor_ids.extend(prev.ids())
                        anchor_texts.extend(prev.texts())
                    elif prev.command in ("tapOn", "inputText"):
                        break
                context_ids = [i for s in window for i in s.ids()]
                producing = [s.summary() for s in window if s.command in INTERESTING]
                ns = namespace_of(anchor_ids) or namespace_of(context_ids)
                screen, text_anchored = screen_of(dest, ns, anchor_texts)
                rec = {
                    "screenshot": dest + ".png",
                    "dest_key": dest,
                    "screen": screen,
                    "state": state_label(dest),
                    "text_anchored": text_anchored,
                    "anchor_texts": anchor_texts[:3],
                    "namespace": ns,
                    "flow": rel,
                    "line": line_no,
                    "step_index": step.index,
                    "conditional": step.is_conditional(),
                    "anchor_ids": sorted(set(anchor_ids)),
                    "context_ids": sorted(set(context_ids)),
                    "producing_steps": producing[-8:],
                }
                records.append(rec)
                flow_shots.append(rec)
            window = []
        if flow_shots:
            per_flow[rel] = flow_shots

    return records, per_flow, subflow_edges, suite_order(repo, flows_dir)


def reachable_from(entry, edges, seen=None):
    seen = seen if seen is not None else set()
    if entry in seen:
        return seen
    seen.add(entry)
    for nxt in edges.get(entry, ()):
        reachable_from(nxt, edges, seen)
    return seen


# ── Verification against a real capture ──────────────────────────────────────

def png_size(path):
    """(width, height) from the PNG IHDR, without PIL."""
    try:
        with open(path, "rb") as fh:
            head = fh.read(33)
        if head[:8] != b"\x89PNG\r\n\x1a\n":
            return None
        return (int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big"))
    except OSError:
        return None


def verify(repo, records, shots_dir):
    root = shots_dir if os.path.isabs(shots_dir) else os.path.join(repo, shots_dir)
    declared = {r["screenshot"] for r in records}
    on_disk = set()
    for dirpath, _dirs, files in os.walk(root):
        for f in files:
            if f.endswith(".png"):
                p = os.path.join(dirpath, f)
                on_disk.add(os.path.relpath(p, repo).replace("\\", "/"))

    missing = sorted(declared - on_disk)
    orphaned = sorted(on_disk - declared)
    sizes = defaultdict(list)
    for rel in sorted(on_disk):
        s = png_size(os.path.join(repo, rel))
        if s:
            sizes[s].append(rel)

    per_dir_sizes = defaultdict(set)
    for size, files in sizes.items():
        for f in files:
            per_dir_sizes[os.path.dirname(f)].add(size)
    mixed = sorted(d for d, s in per_dir_sizes.items() if len(s) > 1)

    return {
        "declared": len(declared),
        "on_disk": len(on_disk),
        "missing": missing,
        "orphaned": orphaned,
        "sizes": {f"{w}x{h}": len(v) for (w, h), v in sorted(sizes.items(), key=lambda kv: -len(kv[1]))},
        "mixed_size_dirs": mixed,
        "clean": not missing and not orphaned and len(sizes) <= 1,
    }


# ── Rendering ────────────────────────────────────────────────────────────────

def render_md(records, per_flow, edges, suite, verification=None,
              registry=None, pin=None, screens_md=None):
    total = len(records)
    flows = len(per_flow)
    screens = OrderedDict()
    for r in records:
        screens.setdefault(r["screen"], []).append(r)

    suite_reach = set()
    for entry in suite:
        norm = os.path.join("shared", "flows", entry)
        suite_reach |= reachable_from(norm, edges)
    covered = [r for r in records if r["flow"] in suite_reach]
    uncovered_flows = sorted({r["flow"] for r in records if r["flow"] not in suite_reach})

    out = []
    A = out.append
    A("# iOS screenshot reference set — screenshot → screen → flow + step")
    A("")
    A("Generated from the Maestro flow YAML by `screenshot_map.py`. Every row is")
    A("anchored to a real `file:line`, so it can be re-generated whenever the flows")
    A("change and diffed against a capture.")
    A("")
    if pin and pin.get("commit"):
        dirty = " + uncommitted working-tree changes" if pin.get("dirty") else ""
        A(f"> Generated from `{pin.get('branch') or '?'}` @ `{pin['commit']}`{dirty}.")
        A("> The flows are under active change (BIT-5 is adding the Android scaffold),")
        A("> so re-generate before treating this as current.")
        A("")
    A("## What this is")
    A("")
    A("Two audiences, one table:")
    A("")
    A("- **Mobile Product Designer (BIT-4)** — the screen inventory. Each distinct")
    A("  screen, the states it is captured in, and the accessibility-id namespace")
    A("  that identifies it.")
    A("- **Android Lead (BIT-5 / BIT-7)** — the behavioural spec. The exact step")
    A("  sequence that reaches each screen, and the accessibility ids that must")
    A("  survive the port as Compose `testTag`s for the Maestro suite to pass on")
    A("  Android.")
    A("")
    A("### This does not replace `shared/docs/screens.md`")
    A("")
    A("The repo already has a hand-written screen inventory. The two are different")
    A("cuts and both are needed:")
    A("")
    A("| | `screens.md` | this document |")
    A("|---|---|---|")
    A("| Unit | one view controller | one `takeScreenshot` step |")
    A("| Written by | hand | generated from the flow YAML |")
    A("| Answers | what a screen *is* and why | which file came from which step |")
    A("| Staleness | drifts silently | re-run the tool |")
    A("")
    A("Use `screens.md` for purpose and VC mapping; use this for the file-level")
    A("index and the id contract. The reconciliation below keeps them honest.")
    A("")
    A(f"**{total} screenshot steps** across **{flows} flows**, covering")
    A(f"**{len(screens)} distinct screens**.")
    A("")
    if verification:
        v = verification
        A("## Capture status")
        A("")
        A(f"- Declared by the flows: **{v['declared']}**")
        A(f"- Present on disk: **{v['on_disk']}**")
        A(f"- Missing: **{len(v['missing'])}** · Orphaned: **{len(v['orphaned'])}**")
        A(f"- Resolutions: {', '.join(f'{k} ({n})' for k, n in v['sizes'].items()) or 'none'}")
        if v["mixed_size_dirs"]:
            A(f"- **Mixed-resolution directories: {len(v['mixed_size_dirs'])}** — "
              f"{', '.join(os.path.basename(d) for d in v['mixed_size_dirs'][:8])}")
        # Two independent verdicts. Device consistency and completeness fail
        # for different reasons and have different fixes, so never collapse
        # them into one line — the old single verdict read "not a clean
        # single-device set" on a set that was perfectly single-device and
        # merely missing a flow nobody had run yet.
        single_device = len(v["sizes"]) <= 1 and not v["mixed_size_dirs"]
        A(f"- Device consistency: "
          f"{'**clean** — every shot from one device' if single_device else '**MIXED — unusable for spacing/type scale**'}")
        A(f"- Completeness: "
          f"{'**complete**' if not v['missing'] else f'''**{len(v['missing'])} of {v['declared']} declared shots absent** — classified below'''}")
        A("")

        if v["missing"]:
            miss = set(v["missing"])
            by_flow_present = Counter(
                r["flow"] for r in records if r["screenshot"] not in miss)
            out_of_scope, never_ran, partial, branch = [], [], [], []
            for r in records:
                if r["screenshot"] not in miss:
                    continue
                if "evil" in r["flow"] or r["flow"].endswith("smoke.yaml"):
                    out_of_scope.append(r)
                elif r["conditional"]:
                    branch.append(r)
                elif by_flow_present[r["flow"]] == 0:
                    never_ran.append(r)
                else:
                    partial.append(r)

            A("### Why each shot is absent")
            A("")
            A("A gap because a flow was never invoked and a gap because a flow died")
            A("half-way look identical in a tarball. They are told apart here by")
            A("whether the step sits inside a `runFlow: when:` guard, and by whether")
            A("the same flow produced any other shot.")
            A("")
            A("| Class | Shots | Means | Action |")
            A("|---|---|---|---|")
            A(f"| Out of scope by design | {len(out_of_scope)} | EvilBoltz + `smoke.yaml`, "
              "deliberately excluded from the target set | none |")
            A(f"| Flow never invoked | {len(never_ran)} | flow produced **zero** shots — "
              "it was not run at all | re-run that flow |")
            A(f"| Flow died part-way | {len(partial)} | flow produced some shots but not "
              "these, and they are unguarded | **investigate — a red flow** |")
            A(f"| Conditional branch not taken | {len(branch)} | step is inside a "
              "`when:` guard that evaluated false; the flow passed | see below |")
            A("")
            if not partial:
                A("**No flow died part-way.** Every gap is a flow that was never "
                  "invoked, a deliberate exclusion, or a branch that did not fire — "
                  "so every flow that ran, ran to completion.")
                A("")
            for label, group in (("Flow never invoked", never_ran),
                                 ("Flow died part-way", partial),
                                 ("Conditional branch not taken", branch)):
                if not group:
                    continue
                A(f"**{label}**")
                A("")
                for flow, n in sorted(Counter(
                        r["flow"] for r in group).items()):
                    shots = sorted(os.path.basename(r["screenshot"])
                                   for r in group if r["flow"] == flow)
                    A(f"- `{flow}` — {n}: "
                      + ", ".join(f"`{s}`" for s in shots))
                A("")
    else:
        A("## Capture status")
        A("")
        A("**Pixels not yet captured.** This revision is the map only — every row")
        A("below is derived from the flows, not from files on disk. When the capture")
        A("lands, re-run with `--verify` and this section reports missing, orphaned")
        A("and mixed-resolution files.")
        A("")

    A("## Coverage — what a plain `test_suite.sh` run does *not* capture")
    A("")
    A(f"`suite.yaml` reaches **{len(covered)} of {total}** screenshot steps.")
    A("The rest need their own invocation:")
    A("")
    if uncovered_flows:
        A("| Flow | Shots | How to run it |")
        A("|---|---|---|")
        for f in uncovered_flows:
            n = len([r for r in records if r["flow"] == f])
            base = os.path.basename(f)
            if "evil" in base:
                how = "`shared/flows/test_suite.sh --evil-only`"
            elif "unhappy" in base:
                how = "`shared/flows/test_suite.sh --unhappy`"
            elif "notification" in base:
                how = f"`shared/flows/test_suite.sh {os.path.relpath(f, 'shared/flows')}`"
            else:
                how = f"`shared/flows/test_suite.sh {os.path.relpath(f, 'shared/flows')}`"
            A(f"| `{os.path.relpath(f, 'shared/flows')}` | {n} | {how} |")
    else:
        A("_None — the suite covers every screenshot step._")
    A("")

    if screens_md:
        rec = reconcile_screens(screens_md, records)
        A("## Reconciliation against `shared/docs/screens.md`")
        A("")
        A(f"`screens.md` documents **{rec['total']} screens**, every one of them")
        A("with a declared screenshot path. Checking those paths against what the")
        A("flows actually produce:")
        A("")
        A(f"- Fully consistent: **{rec['consistent']}**")
        A(f"- Declaring at least one screenshot **no flow produces: "
          f"{len(rec['stale'])}**")
        A("")
        if rec["stale"]:
            A("These are doc-drift, not capture gaps — `screens.md` points at files")
            A("the current flows never write, so a designer following it would look")
            A("for images that will not be in the delivered set:")
            A("")
            A("| Screen | Missing / declared | Paths no flow produces |")
            A("|---|---|---|")
            for s in rec["stale"]:
                paths = ", ".join(f"`{p}`" for p in s["missing"][:4])
                more = f" +{len(s['missing']) - 4} more" if len(s["missing"]) > 4 else ""
                A(f"| {s['name']} | {len(s['missing'])}/{s['total']} | {paths}{more} |")
            A("")

    A("## Screen inventory — the design surface")
    A("")
    A("Grouped by screen, not by file: this is the list the designer draws once")
    A("and the port implements once. **States** are the distinct conditions that")
    A("screen is captured in (loading, filled, error, empty …) — each is a real")
    A("visual the Android version has to reproduce.")
    A("")
    id_backed = sorted((n, rs) for n, rs in screens.items() if not rs[0]["text_anchored"])
    text_only = sorted((n, rs) for n, rs in screens.items() if rs[0]["text_anchored"])
    A(f"**{len(id_backed)} id-backed screens** + {len(text_only)} text-anchored "
      "groups (system alerts / share sheet — no accessibility id to assert on).")
    A("")
    A("| Screen | id namespace | Shots | Distinct states | Flows |")
    A("|---|---|---|---|---|")
    for name, rs in id_backed + text_only:
        ns = rs[0]["namespace"] or "_(text only)_"
        ns = f"`{ns}`" if rs[0]["namespace"] else ns
        n_flows = len({r["flow"] for r in rs})
        states = len({r["state"] for r in rs})
        A(f"| {name} | {ns} | {len(rs)} | {states} | {n_flows} |")
    A("")
    A("<details><summary>States per screen</summary>")
    A("")
    for name, rs in id_backed + text_only:
        sts = sorted({r["state"] for r in rs})
        A(f"**{name}** ({len(sts)}) — " + ", ".join(sts))
        A("")
    A("</details>")
    A("")

    A("## The map — every screenshot, in flow order")
    A("")
    for flow, rs in per_flow.items():
        A(f"### `{os.path.relpath(flow, 'shared/flows')}`")
        A("")
        in_suite = "in `suite.yaml`" if flow in suite_reach else "**separate invocation**"
        A(f"_{len(rs)} screenshots · {in_suite}_")
        A("")
        A("| # | Screenshot | Screen | State | Line | Steps that produce it | Anchor |")
        A("|---|---|---|---|---|---|---|")
        for i, r in enumerate(rs, 1):
            steps = "; ".join(f"`{s}`" for s in r["producing_steps"]) or "_(entry state)_"
            if r["anchor_ids"]:
                anchor = ", ".join(f"`{x}`" for x in r["anchor_ids"][:4])
            elif r["anchor_texts"]:
                anchor = ", ".join(f'text "{t}"' for t in r["anchor_texts"][:2])
            else:
                anchor = "—"
            cond = " ⚠️cond" if r["conditional"] else ""
            A(f"| {i} | `{os.path.basename(r['dest_key'])}.png`{cond} | {r['screen']} | "
              f"{r['state']} | {r['line']} | {steps} | {anchor} |")
        A("")

    A("## Accessibility ids the Android port must preserve")
    A("")
    A("Every id below is asserted or tapped by a flow. The Maestro suite is the")
    A("acceptance gate for the Android app, so each one needs a matching")
    A("`Modifier.testTag(...)` on the Compose side.")
    A("")
    by_ns = defaultdict(set)
    for r in records:
        for i in r["anchor_ids"] + r["context_ids"]:
            if "." in i:
                by_ns[i.split(".")[0]].add(i)
    A("| Namespace | Screen | ids |")
    A("|---|---|---|")
    for ns in sorted(by_ns):
        label = NAMESPACE_LABELS.get(ns, ns.replace("_", " ").title())
        ids = sorted(by_ns[ns])
        A(f"| `{ns}` | {label} | {len(ids)} |")
    A("")

    if registry is not None:
        used = {i for s in by_ns.values() for i in s}
        unregistered = sorted(used - registry)
        unused = sorted(registry - used)
        A("### Reconciliation against `shared/test-ids/test-ids.json`")
        A("")
        A(f"The repo already has a canonical id registry ({len(registry)} ids). The")
        A("port should generate Compose `testTag`s from that file, not from this")
        A("document — but the two need to agree:")
        A("")
        A(f"- Used by a screenshot-producing flow **and** registered: "
          f"**{len(used & registry)}**")
        indexed = [i for i in unregistered if re.search(r"\d+$", i)]
        other = [i for i in unregistered if i not in set(indexed)]
        A(f"- Used by a flow but **not in the registry: {len(unregistered)}**")
        A(f"- Registered but not exercised by any screenshot flow: **{len(unused)}** "
          "(fine — not every id gates a screenshot)")
        A("")
        if indexed:
            A(f"**{len(indexed)} of the unregistered ids are runtime-indexed**, so their")
            A("absence from a static registry is correct — but the port has to build")
            A("them by the same rule or the flows break:")
            A("")
            groups = defaultdict(list)
            for i in indexed:
                groups[re.sub(r"\d+$", "N", i)].append(i)
            for pattern, members in sorted(groups.items()):
                A(f"- `{pattern}` — {len(members)} seen "
                  f"(`{members[0]}` … `{sorted(members)[-1]}`)")
            A("")
        if other:
            A(f"**{len(other)} genuinely unregistered** — these need a registry entry")
            A("before a registry-driven port can assert on them:")
            A("")
            A(", ".join(f"`{i}`" for i in sorted(other)))
            A("")
    A("<details><summary>Full id list</summary>")
    A("")
    for ns in sorted(by_ns):
        A(f"**`{ns}`** — " + ", ".join(f"`{i}`" for i in sorted(by_ns[ns])))
        A("")
    A("</details>")
    A("")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--out-dir", default=".")
    ap.add_argument("--verify", default=None,
                    help="path to a captured screenshots dir to check the map against")
    args = ap.parse_args()

    repo = os.path.abspath(args.repo)
    records, per_flow, edges, suite = build(repo)
    v = verify(repo, records, args.verify) if args.verify else None
    registry = load_registry(repo)
    pin = git_pin(repo)
    screens_md = load_screens_md(repo)

    os.makedirs(args.out_dir, exist_ok=True)
    jpath = os.path.join(args.out_dir, "reference-set.json")
    mpath = os.path.join(args.out_dir, "reference-set.md")
    with open(jpath, "w", encoding="utf-8") as fh:
        json.dump({
            "generated_from": pin,
            "records": records,
            "verification": v,
            "screens_md": reconcile_screens(screens_md, records) if screens_md else None,
        }, fh, indent=2)
    with open(mpath, "w", encoding="utf-8") as fh:
        fh.write(render_md(records, per_flow, edges, suite, v, registry, pin,
                           screens_md))

    print(f"{len(records)} screenshot steps across {len(per_flow)} flows")
    print(f"wrote {jpath}")
    print(f"wrote {mpath}")
    if v:
        print(f"verify: missing={len(v['missing'])} orphaned={len(v['orphaned'])} "
              f"sizes={v['sizes']} clean={v['clean']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
