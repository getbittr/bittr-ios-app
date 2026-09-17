#!/usr/bin/env bash
#
# test_suite_android.sh — run the bittr Maestro suite against the Android app with one command.
#
# The Android twin of test_suite.sh. It takes care of:
#   • preflight checks (adb, maestro, node, a booted device, the app installed)
#   • optionally booting the emulator (--boot) and building + installing the
#     regtest app (--install)
#   • the helper node servers (push_server.js, clipboard_server.js) in their
#     Android mode, pointed at the device under test — started if missing, left
#     alone if already running in Android mode, and only the ones WE started are
#     stopped afterwards
#   • running every flow in shared/flows/suite.yaml, in its hand-ordered
#     dependency sequence, with a pass/fail summary and one log per flow
#
# Usage:
#   shared/flows/test_suite_android.sh                        # full suite
#   shared/flows/test_suite_android.sh --keep-going           # don't stop on first failure
#   shared/flows/test_suite_android.sh --from bitcoin_map     # resume the suite at a flow
#   shared/flows/test_suite_android.sh features/receive.yaml  # just these flows
#   shared/flows/test_suite_android.sh --boot --install ...   # start the emulator and
#                                                             # install the current build first
#   shared/flows/test_suite_android.sh --install-only         # build + install, run nothing
#
# Options:
#   --device SERIAL   device to test on (default: $ANDROID_SERIAL, else the only
#                     emulator attached). Needed when a phone and an emulator are
#                     both connected and you want the phone.
#   --boot            start the emulator (--avd, default bittr-gapi) if none is running
#   --avd NAME        AVD for --boot (default: bittr-gapi — Google APIs image, so the
#                     app gets a real Firebase token; see shared/docs/android-port-decisions.md)
#   --install         build the regtest debug app and install it before running
#   --install-only    like --install, but run no flows
#   --keep-going      run the remaining flows after a failure
#   --from FLOW       start the suite at the first flow whose path contains FLOW
#
# Environment:
#   BITTR_LDK_CHAIN_SOURCE_URL, BITTR_LDK_ELECTRUM_URL, BITTR_LDK_LIGHTNING_NODE_ID,
#   BITTR_LDK_LIGHTNING_NODE_ADDRESS
#                     the regtest node the app connects to, needed by --install.
#                     Read from $BITTR_ANDROID_ENV_FILE (default
#                     ~/.bittr/android-regtest.env) when not already set. Never commit
#                     these (NoCommittedNodeCredentialsTest).
#   APP_ID            default com.bittr.android.regtest
#   BITTR_LOG_DIR     keep this run's logs here instead of a throwaway /tmp dir
#
# Exit code: 0 if everything passed, 1 if any flow failed, 2 on preflight errors.

set -uo pipefail

# ── Setup ────────────────────────────────────────────────────────────────────

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${REPO_ROOT}" ]]; then
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
cd "${REPO_ROOT}" || { echo "cannot cd to ${REPO_ROOT}" >&2; exit 2; }

FLOWS_DIR="shared/flows"
SCRIPTS_DIR="${FLOWS_DIR}/scripts"
LOG_DIR="${BITTR_LOG_DIR:-$(mktemp -d /tmp/bittr-test-suite-android.XXXXXX)}"
mkdir -p "${LOG_DIR}" || { echo "cannot create log dir ${LOG_DIR}" >&2; exit 2; }

PUSH_PORT=8888
CLIPBOARD_PORT=8889

SUITE_FILE="${FLOWS_DIR}/suite.yaml"
CORE_FLOWS=()
while IFS= read -r _flow; do
    [[ -n "${_flow}" ]] && CORE_FLOWS+=("${_flow}")
done < <(grep -E '^[[:space:]]*-[[:space:]]*runFlow:' "${SUITE_FILE}" 2>/dev/null \
         | sed -E 's/^[[:space:]]*-[[:space:]]*runFlow:[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]*$//')

MNEMONIC="attack urge across cupboard year armor list vital outer leader anxiety endorse"
APP_ID="${APP_ID:-com.bittr.android.regtest}"

# How long one flow may run before the watchdog kills it. The slowest (wrong_pin_with_channel,
# which closes a channel; settings) take about fifteen minutes on a loaded emulator.
FLOW_TIMEOUT_SECS="${FLOW_TIMEOUT_SECS:-1800}"
ENV_FILE="${BITTR_ANDROID_ENV_FILE:-${HOME}/.bittr/android-regtest.env}"

# The driver install and first connection are slow on a busy Mac; Maestro's default
# gives up with "Android driver did not start up in time".
export MAESTRO_DRIVER_STARTUP_TIMEOUT="${MAESTRO_DRIVER_STARTUP_TIMEOUT:-180000}"

# ── Options ──────────────────────────────────────────────────────────────────

SERIAL="${ANDROID_SERIAL:-}"
BOOT=0
AVD="bittr-gapi"
INSTALL=0
RUN_FLOWS=1
KEEP_GOING=0
FROM_FLOW=""
EXPLICIT_FLOWS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --device)       shift; SERIAL="${1:-}" ;;
        --device=*)     SERIAL="${1#*=}" ;;
        --boot)         BOOT=1 ;;
        --avd)          shift; AVD="${1:-}" ;;
        --avd=*)        AVD="${1#*=}" ;;
        --install)      INSTALL=1 ;;
        --install-only) INSTALL=1; RUN_FLOWS=0 ;;
        --keep-going)   KEEP_GOING=1 ;;
        --from)         shift; FROM_FLOW="${1:-}"
                        [[ -n "${FROM_FLOW}" ]] || { echo "--from needs a flow (e.g. --from bitcoin_map)" >&2; exit 2; } ;;
        --from=*)       FROM_FLOW="${1#*=}" ;;
        -h|--help)      sed -n '2,46p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)             echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
        *)              EXPLICIT_FLOWS+=("$1") ;;
    esac
    shift
done

if [[ -n "${FROM_FLOW}" ]]; then
    if [[ ${#EXPLICIT_FLOWS[@]} -gt 0 ]]; then
        echo "--from can't be combined with explicit flow paths" >&2; exit 2
    fi
    _start=-1
    for _i in "${!CORE_FLOWS[@]}"; do
        if [[ "${CORE_FLOWS[$_i]}" == *"${FROM_FLOW}"* ]]; then _start=${_i}; break; fi
    done
    if [[ ${_start} -lt 0 ]]; then
        echo "--from: no suite flow matches '${FROM_FLOW}' (see shared/flows/suite.yaml)" >&2; exit 2
    fi
    CORE_FLOWS=("${CORE_FLOWS[@]:${_start}}")
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

# ── Tools ────────────────────────────────────────────────────────────────────

header "Preflight checks"
PREFLIGHT_OK=1

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
[[ -n "${SDK}" && -d "${SDK}/platform-tools" ]] && export PATH="${SDK}/platform-tools:${SDK}/emulator:${PATH}"
if command -v adb >/dev/null 2>&1; then
    ok "adb $(adb version 2>/dev/null | head -1 | awk '{print $NF}')"
else
    fail "adb not found — set ANDROID_HOME to your Android SDK"
    exit 2
fi

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

# ── Device ───────────────────────────────────────────────────────────────────

online_devices() { adb devices 2>/dev/null | awk 'NR>1 && $2=="device" {print $1}'; }
emulators() { online_devices | grep '^emulator-' || true; }

if [[ -z "${SERIAL}" && ${BOOT} -eq 1 && -z "$(emulators)" ]]; then
    if ! command -v emulator >/dev/null 2>&1; then
        fail "--boot: emulator not found — set ANDROID_HOME"; exit 2
    fi
    info "booting ${AVD} (log: ${LOG_DIR}/emulator.log) …"
    # No camera, like CI (the scanner flow expects the "no camera" alert); nohup so the
    # emulator outlives this script.
    nohup emulator -avd "${AVD}" -memory 4096 -cores 6 -no-snapshot-save -noaudio \
        -no-boot-anim -gpu host -camera-back none > "${LOG_DIR}/emulator.log" 2>&1 &
    for _i in $(seq 1 60); do
        [[ -n "$(emulators)" ]] && break
        sleep 3
    done
fi

if [[ -z "${SERIAL}" ]]; then
    _emus="$(emulators)"
    _count="$(printf '%s' "${_emus}" | grep -c . || true)"
    if [[ "${_count}" == "1" ]]; then
        SERIAL="${_emus}"
    elif [[ "${_count}" == "0" && "$(online_devices | grep -c . || true)" == "1" ]]; then
        SERIAL="$(online_devices)"
    else
        fail "can't pick a device — attached: $(online_devices | tr '\n' ' ')"
        fail "pass --device SERIAL (or export ANDROID_SERIAL), or use --boot"
        exit 2
    fi
fi
export ANDROID_SERIAL="${SERIAL}"
dev() { adb -s "${SERIAL}" "$@"; }

if ! online_devices | grep -qx "${SERIAL}"; then
    fail "device ${SERIAL} is not attached (adb devices)"
    exit 2
fi
for _i in $(seq 1 60); do
    [[ "$(dev shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]] && break
    sleep 3
done
if [[ "$(dev shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
    ok "device ${SERIAL} ($(dev shell getprop ro.product.model 2>/dev/null | tr -d '\r'), Android $(dev shell getprop ro.build.version.release 2>/dev/null | tr -d '\r'))"
else
    fail "device ${SERIAL} has not finished booting"
    exit 2
fi

if dev shell pm path com.google.android.gms >/dev/null 2>&1; then
    ok "Google Play services present (real push tokens)"
else
    warn "no Google Play services on ${SERIAL} — no push token, so the signup stops at the token alert and swaps need notifications. Use the bittr-gapi AVD or a phone."
fi

# bitcoin_map.yaml taps "my location" and expects the map, where the app otherwise says
# location details are unavailable. Two things it needs, neither of which Maestro's
# `permissions: location:` delivers on Android (the grant silently does not take —
# `dumpsys package … ACCESS_COARSE_LOCATION: granted=false` after a launch that asked):
# the permission, and a position to read. The iOS simulator is launched with both.
if dev shell pm grant "${APP_ID}" android.permission.ACCESS_COARSE_LOCATION >/dev/null 2>&1; then
    ok "location permission granted to ${APP_ID}"
else
    warn "could not grant the location permission; bitcoin_map's my-location step will fail"
fi

# The emulator's GPS is a one-shot injection that only lands while a client is listening,
# so a single `geo fix` before the run leaves last location=null. Fed in the background
# for as long as the suite runs instead. A phone has its own position.
GEO_FEEDER_PID=""
if [[ "${SERIAL}" == emulator-* ]]; then
    (
        while true; do
            adb -s "${SERIAL}" emu geo fix 8.245 46.897 >/dev/null 2>&1 || exit 0
            sleep 2
        done
    ) &
    GEO_FEEDER_PID=$!
    ok "feeding a location (Sarnen) while the suite runs"
fi

# ── Build + install ──────────────────────────────────────────────────────────

if [[ ${INSTALL} -eq 1 ]]; then
    header "Build + install"
    if [[ -z "${BITTR_LDK_CHAIN_SOURCE_URL:-}" && -f "${ENV_FILE}" ]]; then
        info "reading the regtest node settings from ${ENV_FILE}"
        set -a; source "${ENV_FILE}"; set +a
    fi
    _missing=()
    for _name in BITTR_LDK_CHAIN_SOURCE_URL BITTR_LDK_ELECTRUM_URL BITTR_LDK_LIGHTNING_NODE_ID BITTR_LDK_LIGHTNING_NODE_ADDRESS; do
        [[ -n "${!_name:-}" ]] || _missing+=("${_name}")
    done
    if [[ ${#_missing[@]} -gt 0 ]]; then
        fail "missing ${_missing[*]} — put them in ${ENV_FILE} (KEY=value lines) or export them"
        fail "without them the app builds with no Lightning node and Home never syncs"
        exit 2
    fi
    export BITTR_LDK_CHAIN_SOURCE_URL BITTR_LDK_ELECTRUM_URL BITTR_LDK_LIGHTNING_NODE_ID BITTR_LDK_LIGHTNING_NODE_ADDRESS
    info "./gradlew :app:installDebug (log: ${LOG_DIR}/install.log) …"
    if (cd android && ./gradlew :app:installDebug) > "${LOG_DIR}/install.log" 2>&1; then
        ok "installed ${APP_ID} on ${SERIAL}"
    else
        fail "build/install failed — see ${LOG_DIR}/install.log"
        tail -15 "${LOG_DIR}/install.log" >&2
        exit 2
    fi
    # A fresh debug install runs interpreted and can miss the flows' 15 s launch wait.
    info "compiling ahead of time …"
    dev shell cmd package compile -m speed -f "${APP_ID}" >/dev/null 2>&1 \
        && ok "compiled ahead of time" || warn "ahead-of-time compile failed (launches may be slow)"
    if [[ ${RUN_FLOWS} -eq 0 ]]; then
        exit 0
    fi
fi

if dev shell pm path "${APP_ID}" >/dev/null 2>&1; then
    ok "${APP_ID} installed"
else
    fail "${APP_ID} not installed on ${SERIAL} — re-run with --install"
    PREFLIGHT_OK=0
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
    [[ -n "${GEO_FEEDER_PID}" ]] && kill "${GEO_FEEDER_PID}" 2>/dev/null
    if [[ ${#STARTED_PIDS[@]} -gt 0 ]]; then
        info "stopping helper servers we started (pids: ${STARTED_PIDS[*]})"
        kill "${STARTED_PIDS[@]}" 2>/dev/null || true
    fi
    info "logs: ${LOG_DIR}"
}
trap cleanup EXIT

port_alive() { curl -s -o /dev/null --max-time 2 "http://localhost:$1/" 2>/dev/null; }

# An already-running helper may be the iOS one (xcrun simctl), which would silently
# deliver nothing to Android. macOS `ps eww` shows a process's environment.
server_is_android() {
    local port="$1" pid
    pid="$(lsof -nP -iTCP:"${port}" -sTCP:LISTEN -t 2>/dev/null | head -1)"
    [[ -n "${pid}" ]] && ps eww -p "${pid}" 2>/dev/null | grep -Eq "BITTR_(PUSH|CLIPBOARD)_PLATFORM=android"
}

ensure_server() {
    local name="$1" port="$2" script="$3"
    if port_alive "${port}"; then
        if server_is_android "${port}"; then
            ok "${name} already running on :${port} in Android mode (leaving it)"
            return
        fi
        fail "${name} is already running on :${port}, but not in Android mode (or not started by you)"
        fail "stop it (kill \$(lsof -t -iTCP:${port} -sTCP:LISTEN)) and re-run — this script starts it for Android"
        exit 2
    fi
    info "starting ${name} on :${port} (Android, ${SERIAL}) …"
    BITTR_PUSH_PLATFORM=android BITTR_CLIPBOARD_PLATFORM=android ANDROID_SERIAL="${SERIAL}" \
        BITTR_PUSH_ANDROID_PACKAGE="${APP_ID}" \
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
}

ensure_server "push_server"      "${PUSH_PORT}"      "${SCRIPTS_DIR}/push_server.js"
ensure_server "clipboard_server" "${CLIPBOARD_PORT}" "${SCRIPTS_DIR}/clipboard_server.js"

# ── Run the flows ────────────────────────────────────────────────────────────

FLOWS_TO_RUN=()
if [[ ${#EXPLICIT_FLOWS[@]} -gt 0 ]]; then
    FLOWS_TO_RUN=("${EXPLICIT_FLOWS[@]}")
else
    if [[ ${#CORE_FLOWS[@]} -eq 0 ]]; then
        fail "no flows parsed from ${SUITE_FILE} — is it present and non-empty?"
        exit 2
    fi
    FLOWS_TO_RUN=("${CORE_FLOWS[@]}")
fi

header "Running ${#FLOWS_TO_RUN[@]} flow(s) on ${SERIAL}"

RESULTS=()
FAILURES=0

for flow in "${FLOWS_TO_RUN[@]}"; do
    FLOW_PATH="${flow}"
    [[ -f "${FLOW_PATH}" ]] || FLOW_PATH="${FLOWS_DIR}/${flow}"
    [[ -f "${FLOW_PATH}" ]] || FLOW_PATH="${FLOWS_DIR}/${flow}.yaml"
    if [[ ! -f "${FLOW_PATH}" ]]; then
        fail "no such flow: ${flow}"
        RESULTS+=("${RED}✖${RESET} ${flow} — not found")
        FAILURES=$((FAILURES + 1))
        [[ ${KEEP_GOING} -eq 1 ]] && continue || break
    fi

    FLOW_LOG="${LOG_DIR}/$(printf '%s' "${flow%.yaml}" | tr '/' '_').maestro.log"
    OUT_DIR="${LOG_DIR}/$(printf '%s' "${flow%.yaml}" | tr '/' '_')"

    echo
    info "${BOLD}maestro test ${FLOW_PATH}${RESET}"
    info "  log: ${FLOW_LOG}"
    # Stop the app from the previous flow first. A flow that opens with `clearState` clears
    # a running app's data while its window is still being torn down; Android then times out
    # removing the old task and kills the app Maestro has just launched ("Destroy timeout of
    # remove-task"), leaving a blank screen past wait_for_launch's 15 s.
    dev shell am force-stop "${APP_ID}" >/dev/null 2>&1 || true
    sleep 2
    START_TS=$(date +%s)
    # A watchdog, because maestro can stop without exiting: when a runScript throws (a 429 from
    # the e2e endpoints does it), its JS engine dies with "API object must not be garbage
    # collected" and the process then sits there for ever, holding the whole suite. Killed here,
    # the flow fails and the rest still run.
    (
        waited=0
        while [[ ${waited} -lt ${FLOW_TIMEOUT_SECS} ]]; do
            sleep 10
            waited=$((waited + 10))
        done
        pkill -P $$ -f "maestro" 2>/dev/null || true
    ) &
    WATCHDOG_PID=$!
    if maestro --device "${SERIAL}" test --env APP_ID="${APP_ID}" --env MNEMONIC="${MNEMONIC}" \
            --env SLOW_SYNC=0 --test-output-dir "${OUT_DIR}" \
            "${FLOW_PATH}" 2>&1 | tee "${FLOW_LOG}"; then
        kill "${WATCHDOG_PID}" 2>/dev/null || true
        RESULTS+=("${GREEN}✔${RESET} ${flow} ($(($(date +%s) - START_TS))s)")
    else
        kill "${WATCHDOG_PID}" 2>/dev/null || true
        RESULTS+=("${RED}✖${RESET} ${flow} ($(($(date +%s) - START_TS))s) — log: ${FLOW_LOG}")
        FAILURES=$((FAILURES + 1))
        fail "${flow} failed — full output: ${FLOW_LOG}"
        info "  failure screenshot + hierarchy: ${OUT_DIR}"
        # The app's own view of the failure: crashes and the last bittr log lines.
        dev logcat -d -b crash 2>/dev/null | grep -A3 "FATAL EXCEPTION" | tail -4 | sed 's/^/    crash: /' || true
        if [[ ${KEEP_GOING} -eq 0 ]]; then
            warn "stopping early (use --keep-going to run the rest, or --from to resume)"
            RESULTS+=("${DIM}… skipped remaining flows${RESET}")
            break
        fi
    fi
done

# ── Summary ──────────────────────────────────────────────────────────────────

header "Summary"
for line in "${RESULTS[@]}"; do
    echo "  ${line}"
done
echo

if [[ ${FAILURES} -gt 0 ]]; then
    fail "test suite FAILED (${FAILURES} flow(s))"
    exit 1
fi
ok "test suite passed"
exit 0
