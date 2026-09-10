#!/usr/bin/env bash
#
# bit14_topup.sh — capture the screenshots the 2026-09-09 suite run did not.
#
# The 2026-09-09 pass landed 274 shots and left five gaps. Each needs its own
# app state, and the orderings are easy to get wrong by hand, so they live here
# rather than in a wiki page:
#
#   pass 1  seed_gate                     7 shots  BIT-19, added after the run
#   pass 2  buy_signup_no_notifications  19 shots  notifications DENIED
#   pass 3  notification_*               17 shots  `information` FIRST
#   pass 4  remove_wallet channel arc     7 shots  needs a funded channel
#   pass 5  receive_onchain / S-27        1 shot   needs -slowSync (Swift patch)
#
# Every pass is destructive and self-contained: each starts by wiping or
# cold-launching into the state it needs, so they can be run in any order — but
# the order below is the cheapest, because it front-loads the short ones.
#
# Usage:
#   shared/flows/bit14_topup.sh                # all five passes, then verify
#   shared/flows/bit14_topup.sh --from 4       # resume at pass 4 after a failure
#   shared/flows/bit14_topup.sh --only 3       # just one pass
#   shared/flows/bit14_topup.sh --skip-s27     # no Swift patch built yet
#   shared/flows/bit14_topup.sh --verify-only  # just re-run the verifier
#
# Expect ~60–90 min for the full set. Preflight (simulator, maestro, helper
# servers) is handled by test_suite.sh, which every pass goes through.
#
# Exit code: 0 if every pass ran green, 1 otherwise.

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${REPO_ROOT}" ]]; then
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
cd "${REPO_ROOT}" || { echo "cannot cd to ${REPO_ROOT}" >&2; exit 2; }

SUITE="shared/flows/test_suite.sh"
SHOTS="shared/docs/screenshots"
MAP="shared/docs/screenshot_map.py"

# Seconds to hold the sync overlay open in pass 5. See
# shared/docs/sync_overlay_capture.md — this only bites if the Swift patch in
# that doc has been applied to the build under test.
SLOW_SYNC_SECONDS="${BITTR_SLOW_SYNC:-20}"

# ── Options ──────────────────────────────────────────────────────────────────

FROM_PASS=1
ONLY_PASS=0
SKIP_S27=0
VERIFY_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --from)        shift; FROM_PASS="${1:-1}" ;;
        --from=*)      FROM_PASS="${1#*=}" ;;
        --only)        shift; ONLY_PASS="${1:-0}" ;;
        --only=*)      ONLY_PASS="${1#*=}" ;;
        --skip-s27)    SKIP_S27=1 ;;
        --verify-only) VERIFY_ONLY=1 ;;
        -h|--help)     sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
        *)             echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
    shift
done

# ── Pretty printing ──────────────────────────────────────────────────────────

if [[ -t 1 ]]; then
    BOLD=$'\033[1m'; GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'
    DIM=$'\033[2m'; RESET=$'\033[0m'
else
    BOLD=""; GREEN=""; RED=""; YELLOW=""; DIM=""; RESET=""
fi

ok()   { echo "${GREEN}✔${RESET} $*"; }
warn() { echo "${YELLOW}⚠${RESET} $*"; }
fail() { echo "${RED}✖${RESET} $*" >&2; }
banner() {
    echo
    echo "${BOLD}────────────────────────────────────────────────────────────${RESET}"
    echo "${BOLD}  $*${RESET}"
    echo "${BOLD}────────────────────────────────────────────────────────────${RESET}"
}

RESULTS=()
FAILED=0

# should_run <pass-number>
should_run() {
    local n="$1"
    [[ ${VERIFY_ONLY} -eq 1 ]] && return 1
    if [[ ${ONLY_PASS} -ne 0 ]]; then [[ "${n}" -eq "${ONLY_PASS}" ]]; return; fi
    [[ "${n}" -ge "${FROM_PASS}" ]]
}

# run_pass <number> <label> <expected-shots> -- <command...>
run_pass() {
    local n="$1" label="$2" shots="$3"; shift 4
    banner "Pass ${n}/5 — ${label}  (${shots} shots)"
    echo "${DIM}\$ $*${RESET}"
    local start; start=$(date +%s)
    if "$@"; then
        local secs=$(($(date +%s) - start))
        ok "pass ${n} (${label}) — ${secs}s"
        RESULTS+=("${GREEN}✔${RESET} ${n}. ${label} (${shots} shots, ${secs}s)")
    else
        local secs=$(($(date +%s) - start))
        fail "pass ${n} (${label}) failed after ${secs}s"
        RESULTS+=("${RED}✖${RESET} ${n}. ${label} — FAILED")
        FAILED=1
        warn "resume with: ${BASH_SOURCE[0]} --from ${n}"
    fi
}

# ── Pass 1: the onboarding seed gate (BIT-19) ────────────────────────────────
# Added to suite.yaml after the 2026-09-09 capture, so it has never been shot.
# Self-contained (clearState) and leaves a throwaway wallet on Signup7, which
# pass 2's clearState wipes.
if should_run 1; then
    run_pass 1 "seed_gate" 7 -- \
        "${SUITE}" onboarding/seed_gate_rejects_wrong_words.yaml
fi

# ── Pass 2: buy signup with notifications DENIED ─────────────────────────────
# fresh_install_skip_signup gives buy_signup_no_notifications the empty-state Buy
# screen it needs. Run bare (not via test_suite.sh) exactly as BIT-14 specifies.
if should_run 2; then
    run_pass 2 "buy_signup_no_notifications" 19 -- bash -c '
        set -e
        maestro test shared/flows/onboarding/fresh_install_skip_signup.yaml
        '"${SUITE}"' features/buy_signup_no_notifications.yaml
    '
fi

# ── Pass 3: the push-notification screens ────────────────────────────────────
# Order is load-bearing. notification_information auto-provisions the wallet and
# leaves the app UNLOCKED on Home; the other two must fire their push on the PIN
# screen, which they reach by cold-launching (a relaunch resets userHasSignedIn,
# so an existing wallet always opens locked). Keep them in ONE invocation.
if should_run 3; then
    run_pass 3 "notification_*" 17 -- \
        "${SUITE}" \
        features/notification_information.yaml \
        features/notification_htlcincoming.yaml \
        features/notification_lnurl.yaml
fi

# ── Pass 4: the remove-wallet channel-close arc ──────────────────────────────
# remove_wallet branches on output.hasChannel, which is ALWAYS false in suite
# order (restore_wallet re-creates a channel-less wallet right before it). This
# sub-suite builds a funded, channelled wallet first so the arc actually fires.
if should_run 4; then
    run_pass 4 "remove_wallet channel arc" 7 -- \
        "${SUITE}" suite_remove_wallet_channel.yaml
fi

# ── Pass 5: the sync status overlay (design-system S-27) ─────────────────────
# Needs the -slowSync patch from shared/docs/sync_overlay_capture.md applied AND
# built. Without it this pass still runs green and simply re-captures
# 00_move_balance.png — the other branch — so a green run here is not proof.
if should_run 5 && [[ ${SKIP_S27} -eq 0 ]]; then
    if ! grep -rq "slowSync" ios/ 2>/dev/null; then
        warn "no 'slowSync' found under ios/ — the Swift patch in"
        warn "shared/docs/sync_overlay_capture.md looks unapplied."
        warn "Pass 5 would re-capture 00_move_balance.png instead of S-27."
        warn "Apply + build it, or re-run with --skip-s27."
        RESULTS+=("${YELLOW}⊘${RESET} 5. receive_onchain / S-27 — skipped, patch not applied")
    else
        run_pass 5 "receive_onchain / S-27" 1 -- \
            env BITTR_SLOW_SYNC="${SLOW_SYNC_SECONDS}" \
            "${SUITE}" features/receive_onchain.yaml
    fi
elif should_run 5; then
    RESULTS+=("${DIM}⊘${RESET} 5. receive_onchain / S-27 — skipped (--skip-s27)")
fi

# ── Leave onboarding/ coherent ───────────────────────────────────────────────
# Passes 2–4 each rewrite onboarding/01–20 from the skip-signup variant. Replay
# the canonical fresh_install last so those shots match the documented happy
# path. Same build, so this is an equivalent re-capture, not a different one.
if [[ ${VERIFY_ONLY} -eq 0 && ${ONLY_PASS} -eq 0 ]]; then
    banner "Re-capturing onboarding/ from the canonical fresh_install"
    if maestro test shared/flows/onboarding/fresh_install.yaml; then
        ok "onboarding/ is coherent"
    else
        warn "fresh_install re-capture failed — onboarding/01–20 may be a mix"
        FAILED=1
    fi
fi

# ── Verify ───────────────────────────────────────────────────────────────────
banner "Verifying against the step-level map"

# --out-dir to scratch: the map always writes reference-set.{json,md} beside
# --repo, and we do not want an untracked pair in the repo root on every run.
# Regenerating the committed set is a deliberate step, printed at the end.
VERIFY_TMP="$(mktemp -d)"
VERIFY_OUT="$(python3 "${MAP}" --repo . --out-dir "${VERIFY_TMP}" --verify "${SHOTS}" 2>&1)"
rm -rf "${VERIFY_TMP}"
echo "${VERIFY_OUT}"

echo
echo "${BOLD}Pass summary${RESET}"
# ${arr[@]} on an empty array is an unbound-variable error under `set -u` in
# bash 3.2, which is what macOS still ships as /bin/bash.
if [[ ${#RESULTS[@]} -gt 0 ]]; then
    for r in "${RESULTS[@]}"; do echo "  ${r}"; done
else
    echo "  ${DIM}(no passes run)${RESET}"
fi

# The floor: 7 EvilBoltz/smoke exclusions (BIT-3 reference-set) + 4 benign
# "conditional branch not taken" misses, and S-27 makes it 12 if it did not land.
cat <<EOF

${BOLD}Expected floor${RESET}
  11 missing — everything captured (7 EvilBoltz/smoke exclusions +
               4 benign conditional-branch misses)
  12 missing — same, but S-27 did not land
  Anything higher means a pass above did not capture what it should have.

Regenerate the BIT-3 reference set on top once this reads clean:
  python3 ${MAP} --repo . --out-dir shared/docs
EOF

if [[ ${FAILED} -ne 0 ]]; then
    echo
    fail "at least one pass failed — see the summary above"
    exit 1
fi
exit 0
