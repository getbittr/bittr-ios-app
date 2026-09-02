#!/usr/bin/env bash
#
# test_suite.sh — run the bittr iOS Maestro suite with one command.
#
# Takes care of everything the README's "Each test run" section does manually:
#   • preflight checks (xcode-select, maestro, node, booted simulator, apps)
#   • the helper node servers (push_server.js, clipboard_server.js, and
#     screenshot_server.js when needed) — started if missing, left alone if
#     already running, and only the ones WE started are stopped afterwards
#   • running the stateful flows in a valid order (fresh install → channel →
#     swaps …) with a pass/fail summary
#
# Usage:
#   shared/flows/test_suite.sh                 # core suite (see CORE_FLOWS)
#   shared/flows/test_suite.sh --evil          # core suite + EvilBoltz flows
#   shared/flows/test_suite.sh --evil-only     # just the EvilBoltz flows
#   shared/flows/test_suite.sh features/swap.yaml features/receive.yaml
#   shared/flows/test_suite.sh --keep-going ...# don't stop on first failure
#   shared/flows/test_suite.sh --expect-vulnerable ...  # evil-flow failures
#                                              # count as EXPECTED (red run on
#                                              # an unfixed build), not errors
#   shared/flows/test_suite.sh --unhappy       # onboarding unhappy path
#                                              # (starts screenshot_server.js —
#                                              # needs Accessibility permission)
#
# Exit code: 0 if everything passed, 1 if any flow failed (unless
# --expect-vulnerable made those failures expected), 2 on preflight errors.

set -uo pipefail

# ── Setup ────────────────────────────────────────────────────────────────────

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${REPO_ROOT}" ]]; then
    # Fallback: two levels up from this script (shared/flows/).
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
cd "${REPO_ROOT}" || { echo "cannot cd to ${REPO_ROOT}" >&2; exit 2; }

FLOWS_DIR="shared/flows"
SCRIPTS_DIR="${FLOWS_DIR}/scripts"
LOG_DIR="$(mktemp -d /tmp/bittr-test-suite.XXXXXX)"

# Helper servers: name → port. Screenshot server is opt-in (--unhappy).
PUSH_PORT=8888
CLIPBOARD_PORT=8889
SCREENSHOT_PORT=8890

# The core suite: a stateful chain (each flow depends on the state the
# previous ones leave behind — do not reorder lightly).
CORE_FLOWS=(
    "onboarding/fresh_install.yaml"   # wipe → create wallet → bittr signup
    "features/buy_incoming.yaml"      # first deposit → opens lightning channel
    "features/buy_more.yaml"          # second deposit on the existing channel
    "features/swap.yaml"              # both swap legs (needs the channel)
)

EVIL_FLOWS=(
    "features/evil_boltz_wrong_invoice.yaml"   # SEC-01 reverse-swap tamper
    "features/evil_boltz_wrong_address.yaml"   # SEC-02 submarine-swap tamper
)

UNHAPPY_FLOWS=(
    "onboarding/fresh_install_unhappy.yaml"
)

# ── Options ──────────────────────────────────────────────────────────────────

RUN_CORE=1
RUN_EVIL=0
RUN_UNHAPPY=0
KEEP_GOING=0
EXPECT_VULNERABLE=0
EXPLICIT_FLOWS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --evil)              RUN_EVIL=1 ;;
        --evil-only)         RUN_EVIL=1; RUN_CORE=0 ;;
        --unhappy)           RUN_UNHAPPY=1 ;;
        --keep-going)        KEEP_GOING=1 ;;
        --expect-vulnerable) EXPECT_VULNERABLE=1 ;;
        -h|--help)
            sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
            exit 0
            ;;
        -*)
            echo "Unknown option: $1 (try --help)" >&2
            exit 2
            ;;
        *)
            EXPLICIT_FLOWS+=("$1") ;;
    esac
    shift
done

if [[ ${#EXPLICIT_FLOWS[@]} -gt 0 ]]; then
    RUN_CORE=0
fi

# ── Pretty printing ──────────────────────────────────────────────────────────

if [[ -t 1 ]]; then
    BOLD=$'\033[1m'; GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
    BOLD=""; GREEN=""; RED=""; YELLOW=""; DIM=""; RESET=""
fi

info()  { echo "${DIM}▸${RESET} $*"; }
ok()    { echo "${GREEN}✔${RESET} $*"; }
warn()  { echo "${YELLOW}⚠${RESET} $*"; }
fail()  { echo "${RED}✖${RESET} $*" >&2; }
header(){ echo; echo "${BOLD}$*${RESET}"; }

# ── Preflight ────────────────────────────────────────────────────────────────

header "Preflight checks"

PREFLIGHT_OK=1

# xcode-select must point at Xcode, not the Command Line Tools (maestro needs
# simctl — README troubleshooting).
XCODE_DIR="$(xcode-select -p 2>/dev/null || true)"
if [[ "${XCODE_DIR}" == *"Xcode.app"* ]]; then
    ok "xcode-select → ${XCODE_DIR}"
else
    fail "xcode-select points at '${XCODE_DIR}' — run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    PREFLIGHT_OK=0
fi

# maestro (also look in the default installer location).
if ! command -v maestro >/dev/null 2>&1 && [[ -x "${HOME}/.maestro/bin/maestro" ]]; then
    export PATH="${HOME}/.maestro/bin:${PATH}"
fi
if command -v maestro >/dev/null 2>&1; then
    ok "maestro $(maestro --version 2>/dev/null | tail -1)"
else
    fail "maestro not found — install: curl -fsSL 'https://get.maestro.mobile.dev' | bash"
    PREFLIGHT_OK=0
fi

if command -v node >/dev/null 2>&1; then
    ok "node $(node --version)"
else
    fail "node not found — brew install node"
    PREFLIGHT_OK=0
fi

# A booted simulator with the app(s) installed.
BOOTED_UDID="$(xcrun simctl list devices booted 2>/dev/null | grep -m1 -E '\([0-9A-F-]+\) \(Booted\)' | sed -E 's/.*\(([0-9A-F-]+)\) \(Booted\).*/\1/' || true)"
if [[ -z "${BOOTED_UDID}" ]]; then
    # Older simctl output format: "iPhone 15 (UDID) (Booted)".
    BOOTED_UDID="$(xcrun simctl list devices 2>/dev/null | grep -m1 '(Booted)' | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/' || true)"
fi
if [[ -n "${BOOTED_UDID}" ]]; then
    ok "booted simulator ${BOOTED_UDID}"
else
    fail "no booted simulator — open one via Xcode and install the app first"
    PREFLIGHT_OK=0
fi

app_installed() { xcrun simctl get_app_container booted "$1" app >/dev/null 2>&1; }

if [[ -n "${BOOTED_UDID}" ]]; then
    if app_installed "com.bittr.bittr-regtest"; then
        ok "bittr regtest installed"
    else
        fail "bittr regtest not installed — build & run the 'bittr' scheme (Debug) in Xcode once"
        PREFLIGHT_OK=0
    fi
    if [[ ${RUN_EVIL} -eq 1 ]]; then
        if app_installed "com.bittr.bittr-evil"; then
            ok "bittr evil installed"
        else
            fail "bittr evil not installed — build & run the 'bittr evil' scheme in Xcode once"
            PREFLIGHT_OK=0
        fi
    fi
fi

if [[ ${PREFLIGHT_OK} -eq 0 ]]; then
    echo
    fail "Preflight failed — fix the above and re-run."
    exit 2
fi

# ── Helper servers ───────────────────────────────────────────────────────────

header "Helper servers"

STARTED_PIDS=()
cleanup() {
    if [[ ${#STARTED_PIDS[@]} -gt 0 ]]; then
        info "stopping helper servers we started (pids: ${STARTED_PIDS[*]})"
        kill "${STARTED_PIDS[@]}" 2>/dev/null || true
    fi
    info "server logs: ${LOG_DIR}"
}
trap cleanup EXIT

port_alive() {
    # Any HTTP response (even the 404 these servers give non-POST paths) means alive.
    curl -s -o /dev/null --max-time 2 "http://localhost:$1/" 2>/dev/null
}

ensure_server() {
    local name="$1" port="$2" script="$3"
    if port_alive "${port}"; then
        ok "${name} already running on :${port} (leaving it)"
    else
        info "starting ${name} on :${port} …"
        nohup node "${script}" > "${LOG_DIR}/${name}.log" 2>&1 &
        STARTED_PIDS+=($!)
        local waited=0
        until port_alive "${port}" || [[ ${waited} -ge 50 ]]; do
            sleep 0.1; waited=$((waited + 1))
        done
        if port_alive "${port}"; then
            ok "${name} up (log: ${LOG_DIR}/${name}.log)"
        else
            fail "${name} did not come up — see ${LOG_DIR}/${name}.log"
            exit 2
        fi
    fi
}

ensure_server "push_server"      "${PUSH_PORT}"       "${SCRIPTS_DIR}/push_server.js"
ensure_server "clipboard_server" "${CLIPBOARD_PORT}"  "${SCRIPTS_DIR}/clipboard_server.js"
if [[ ${RUN_UNHAPPY} -eq 1 ]]; then
    ensure_server "screenshot_server" "${SCREENSHOT_PORT}" "${SCRIPTS_DIR}/screenshot_server.js"
    warn "screenshot flows need Settings > General > Screen Capture > Full-Screen Previews OFF on the device"
fi

# ── Run the flows ────────────────────────────────────────────────────────────

FLOWS_TO_RUN=()
[[ ${RUN_CORE} -eq 1 ]]   && FLOWS_TO_RUN+=("${CORE_FLOWS[@]}")
[[ ${RUN_UNHAPPY} -eq 1 ]] && FLOWS_TO_RUN+=("${UNHAPPY_FLOWS[@]}")
[[ ${#EXPLICIT_FLOWS[@]} -gt 0 ]] && FLOWS_TO_RUN+=("${EXPLICIT_FLOWS[@]}")
[[ ${RUN_EVIL} -eq 1 ]]   && FLOWS_TO_RUN+=("${EVIL_FLOWS[@]}")

if [[ ${#FLOWS_TO_RUN[@]} -eq 0 ]]; then
    fail "nothing to run"
    exit 2
fi

header "Running ${#FLOWS_TO_RUN[@]} flow(s)"
[[ ${EXPECT_VULNERABLE} -eq 1 ]] && warn "--expect-vulnerable: EvilBoltz flow failures count as expected (red run on an unfixed build)"

RESULTS=()
FAILED=0
UNEXPECTED_FAILURES=0

for flow in "${FLOWS_TO_RUN[@]}"; do
    # Allow passing just a path fragment (features/swap.yaml) or a full path.
    FLOW_PATH="${flow}"
    [[ -f "${FLOW_PATH}" ]] || FLOW_PATH="${FLOWS_DIR}/${flow}"

    echo
    info "${BOLD}maestro test ${FLOW_PATH}${RESET}"
    START_TS=$(date +%s)
    if maestro test "${FLOW_PATH}"; then
        RESULTS+=("${GREEN}✔${RESET} ${flow} ($(($(date +%s) - START_TS))s)")
    else
        EXPECTED=0
        if [[ ${EXPECT_VULNERABLE} -eq 1 && "${flow}" == *"evil_boltz_"* ]]; then
            EXPECTED=1
        fi
        if [[ ${EXPECTED} -eq 1 ]]; then
            RESULTS+=("${YELLOW}✖${RESET} ${flow} — failed as expected (vulnerable build)")
            warn "${flow} failed as expected — this build is VULNERABLE (see SECURITY_REVIEW.md)"
        else
            RESULTS+=("${RED}✖${RESET} ${flow} ($(($(date +%s) - START_TS))s)")
            UNEXPECTED_FAILURES=$((UNEXPECTED_FAILURES + 1))
            if [[ ${KEEP_GOING} -eq 0 ]]; then
                warn "stopping early (use --keep-going to run the rest)"
                RESULTS+=("${DIM}… skipped remaining flows${RESET}")
                break
            fi
        fi
        FAILED=1
    fi
done

# ── Summary ──────────────────────────────────────────────────────────────────

header "Summary"
for line in "${RESULTS[@]}"; do
    echo "  ${line}"
done
echo

if [[ ${UNEXPECTED_FAILURES} -gt 0 ]]; then
    fail "test suite FAILED (${UNEXPECTED_FAILURES} flow(s))"
    exit 1
elif [[ ${FAILED} -eq 1 ]]; then
    ok "test suite passed (with expected EvilBoltz failures)"
    exit 0
else
    ok "test suite passed"
    exit 0
fi
