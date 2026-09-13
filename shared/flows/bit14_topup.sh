#!/usr/bin/env bash
#
# bit14_topup.sh — capture the screenshots the 2026-09-09 suite run did not.
#
# The 2026-09-09 pass landed 274 shots. The 2026-09-10 Mac attempt took that to
# 297 but stopped part-way through passes 1 and 2. Each pass needs its own app
# state, and the orderings are easy to get wrong by hand, so they live here
# rather than in a wiki page.
#
# Counts below are what is ACTUALLY still missing, re-derived 2026-09-12 against
# ios-parity (`screenshot_map.py --verify`), not what the passes would shoot
# from scratch:
#
#   pass 1  seed_gate                     6 shots  BIT-19; 1/7 landed 2026-09-10
#   pass 2  buy_signup_no_notifications  14 shots  notifications DENIED; 4 landed
#   pass 3  notification_*                0 shots  COMPLETE 2026-09-10 — skipped
#                                                  by default, --with-notifications
#   pass 4  remove_wallet arc + LNURL    14 shots  needs a funded channel
#   pass 5  receive_onchain / S-27        1 shot   needs -slowSync (Swift patch)
#
# Pass 4 grew: features/receive_lnurl.yaml (BIT-10) landed on ios-parity after
# this list was first written and has never been captured. It needs an open
# channel, which pass 4 has already built, so it rides along there instead of
# paying for a second ~20-minute channel build. See suite_remove_wallet_channel.
#
# Every pass is destructive and self-contained: each starts by wiping or
# cold-launching into the state it needs, so they can be run in any order — but
# the order below is the cheapest, because it front-loads the short ones.
#
# Usage:
#   shared/flows/bit14_topup.sh                # every outstanding pass, + verify
#   shared/flows/bit14_topup.sh --from 4       # resume at pass 4 after a failure
#   shared/flows/bit14_topup.sh --only 3       # just one pass (overrides skips)
#   shared/flows/bit14_topup.sh --skip-s27     # no Swift patch built yet
#   shared/flows/bit14_topup.sh --with-notifications  # re-shoot pass 3 anyway
#   shared/flows/bit14_topup.sh --verify-only  # just re-run the verifier
#
# Expect ~50–75 min now that pass 3 is skipped. Preflight (simulator, maestro,
# helper servers) is handled by test_suite.sh, which every pass goes through.
#
# Exit code: 0 if every pass ran green, 1 otherwise.

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${REPO_ROOT}" ]]; then
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
cd "${REPO_ROOT}" || { echo "cannot cd to ${REPO_ROOT}" >&2; exit 2; }

SUITE="shared/flows/test_suite.sh"

# Two passes below call `maestro test` directly rather than through
# test_suite.sh, and a bare call is NOT equivalent: no flow names an app id —
# every one declares `appId: ${APP_ID}` and the runner supplies it (see
# shared/flows/README.md, "App id"). test_suite.sh passes `--env APP_ID`; a bare
# call leaves the header unresolved and the flow dies at launchApp, seconds in.
# APP_ID is the only variable either bare-run flow resolves — checked across the
# transitive closure of both, which is wait_for_launch + happy_path_wallet
# (+ happy_path_signup for fresh_install); fresh_install's ${EVIL_APP_ID} is in
# a comment. Same default as test_suite.sh, and exported so the passes that DO
# go through it agree with the two that do not.
export APP_ID="${APP_ID:-com.bittr.bittr-regtest}"

# Where this run's Maestro logs go — one file per flow, under a per-pass dir.
# test_suite.sh defaults to a throwaway /tmp dir, which is the wrong default for
# a 60–90 minute unattended pass: the 2026-09-10 attempt stopped part-way
# through two of these passes and left nothing behind to say why. Gitignored.
LOG_ROOT="${BITTR_LOG_DIR:-shared/flows/logs/$(date +%Y%m%d-%H%M%S)}"
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
WITH_NOTIFICATIONS=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --from)        shift; FROM_PASS="${1:-1}" ;;
        --from=*)      FROM_PASS="${1#*=}" ;;
        --only)        shift; ONLY_PASS="${1:-0}" ;;
        --only=*)      ONLY_PASS="${1#*=}" ;;
        --skip-s27)    SKIP_S27=1 ;;
        --with-notifications) WITH_NOTIFICATIONS=1 ;;
        --verify-only) VERIFY_ONLY=1 ;;
        -h|--help)     sed -n '2,44p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
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
    local pass_logs="${LOG_ROOT}/pass${n}"
    echo "${DIM}  logs: ${pass_logs}${RESET}"
    local start; start=$(date +%s)
    if BITTR_LOG_DIR="${pass_logs}" "$@"; then
        local secs=$(($(date +%s) - start))
        ok "pass ${n} (${label}) — ${secs}s"
        RESULTS+=("${GREEN}✔${RESET} ${n}. ${label} (${shots} shots, ${secs}s)")
    else
        local secs=$(($(date +%s) - start))
        fail "pass ${n} (${label}) failed after ${secs}s"
        RESULTS+=("${RED}✖${RESET} ${n}. ${label} — FAILED (logs: ${pass_logs})")
        FAILED=1
        warn "logs for this pass: ${pass_logs}"
        warn "resume with: ${BASH_SOURCE[0]} --from ${n}"
    fi
}

# ── Pass 1: the onboarding seed gate (BIT-19) ────────────────────────────────
# Added to suite.yaml after the 2026-09-09 capture. The 2026-09-10 attempt got
# one shot in (01_verify_initial) and stopped; 02–07 are still missing. Whatever
# stopped it left no artefact — that is what BITTR_LOG_DIR below now fixes, so
# if it stops again the log says why. Self-contained (clearState); leaves a
# throwaway wallet on Signup7, which pass 2's clearState wipes.
if should_run 1; then
    run_pass 1 "seed_gate" 6 -- \
        "${SUITE}" onboarding/seed_gate_rejects_wrong_words.yaml
fi

# ── Pass 2: buy signup with notifications DENIED ─────────────────────────────
# fresh_install_skip_signup gives buy_signup_no_notifications the empty-state Buy
# screen it needs. Run bare (not via test_suite.sh) exactly as BIT-14 specifies.
if should_run 2; then
    run_pass 2 "buy_signup_no_notifications" 14 -- bash -c '
        set -e
        maestro test --env APP_ID="$APP_ID" \
            shared/flows/onboarding/fresh_install_skip_signup.yaml
        '"${SUITE}"' features/buy_signup_no_notifications.yaml
    '
fi

# ── Pass 3: the push-notification screens ────────────────────────────────────
# DONE. All 17 landed on 2026-09-10 and are on disk; the verifier reports none
# of them missing. Re-running costs ~15 minutes of a scarce Mac sitting to
# re-shoot what is already there, so it is skipped by default — the shots do
# not expire, and passes 2/4 below do not touch notification_*.
#
# Order is load-bearing if you DO re-run it (--with-notifications).
# notification_information auto-provisions the wallet and leaves the app
# UNLOCKED on Home; the other two must fire their push on the PIN screen, which
# they reach by cold-launching (a relaunch resets userHasSignedIn, so an
# existing wallet always opens locked). Keep them in ONE invocation.
if should_run 3 && [[ ${WITH_NOTIFICATIONS} -eq 1 || ${ONLY_PASS} -eq 3 ]]; then
    run_pass 3 "notification_*" 17 -- \
        "${SUITE}" \
        features/notification_information.yaml \
        features/notification_htlcincoming.yaml \
        features/notification_lnurl.yaml
elif should_run 3; then
    RESULTS+=("${DIM}⊘${RESET} 3. notification_* — skipped, already complete (--with-notifications to re-shoot)")
fi

# ── Pass 4: the remove-wallet channel-close arc, plus LNURL Receive ──────────
# remove_wallet branches on output.hasChannel, which is ALWAYS false in suite
# order (restore_wallet re-creates a channel-less wallet right before it). This
# sub-suite builds a funded, channelled wallet first so the arc actually fires.
# That channel is also what features/receive_lnurl.yaml (BIT-10) needs, so the
# sub-suite runs it on the way past — 7 arc shots + 7 of LNURL's 8 (its two
# 03a/03b branches are mutually exclusive). This is the longest pass; if the
# sitting runs short, it is the one to protect.
if should_run 4; then
    run_pass 4 "remove_wallet arc + LNURL" 14 -- \
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
    if maestro test --env APP_ID="${APP_ID}" \
            shared/flows/onboarding/fresh_install.yaml; then
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

# The floor: 7 EvilBoltz/smoke exclusions (BIT-3 reference-set) + 6 benign
# "conditional branch not taken" misses, and S-27 makes it 14 if it did not
# land. Re-derived 2026-09-12 against ios-parity: receive_lnurl (BIT-10) added
# a sixth benign branch, so this is 13/14, not the 12/13 it read before.
cat <<EOF

${BOLD}Expected floor${RESET}
  13 missing — everything captured (7 EvilBoltz/smoke exclusions +
               6 benign conditional-branch misses)
  14 missing — same, but S-27 did not land
  Anything higher means a pass above did not capture what it should have.

  The 7 excluded: evil_boltz_wrong_address x2, evil_fund_onchain x2,
  evil_boltz_wrong_invoice, evil_bootstrap, smoke/01_initial.
  The 6 benign: buy_signup_no_notifications/05_notifications_prompt,
  send_onchain/05_success, send_onchain_all/05_success,
  settings/12_peer_disconnected, fresh_install_unhappy/06_screenshot_warning,
  and whichever of receive_lnurl/03a_lnurl_unavailable | 03b_lnurl_address did
  not fire (they are mutually exclusive \`when:\` branches — exactly one can)
  (+ receive_onchain/00_sync_status when S-27 does not land).

  Two lines in the verifier output above are expected and are NOT gaps:
    orphaned=1     android_scaffold_smoke/01_signup_start.png — an Android
                   scaffold shot (1080x2400) parked in the iOS set; it is why
                   clean= never reads True and why sizes= shows two entries.
    out_of_scope=1 device-checks/iphone_se/01_powered_by_alert.png — the BIT-82
                   iPhone SE frame, deliberately captured outside the canonical
                   set. Do not "fix" this by pointing it at screenshots/: a
                   differently-sized frame in there is the BIT-3 defect.

Regenerate the BIT-3 reference set on top once this reads clean:
  python3 ${MAP} --repo . --out-dir shared/docs
EOF

if [[ ${FAILED} -ne 0 ]]; then
    echo
    fail "at least one pass failed — see the summary above"
    exit 1
fi
exit 0
