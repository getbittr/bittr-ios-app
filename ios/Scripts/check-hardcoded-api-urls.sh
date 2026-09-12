#!/bin/sh
#
# Fail the build when a bittr API URL is hard-coded instead of being built from
# BittrAPIEnvironment.baseURL (or its forwarder, EnvironmentConfig.bittrAPIBaseURL).
#
# Why: a literal "https://getbittr.com/api/..." makes a DEBUG/regtest build talk
# to PRODUCTION. For /price/btc that is harmless, but /notifications is
# authenticated by a lightning-pubkey signature, so a test build ends up reading
# real customer payout state. BIT-32 found seven such literals that had
# accumulated independently, which is why this is enforced rather than reviewed.
#
# Run manually from the repo root:  sh ios/Scripts/check-hardcoded-api-urls.sh
# Also wired as the "Check hard-coded API URLs" build phase on the bittr target.

set -eu

# Resolve the ios/ directory whether we are run from a build phase (SRCROOT is
# ios/) or by hand from the repo root.
if [ -n "${SRCROOT:-}" ] && [ -d "${SRCROOT}/bittr" ]; then
    IOS_DIR="${SRCROOT}"
elif [ -d "ios/bittr" ]; then
    IOS_DIR="ios"
elif [ -d "bittr" ]; then
    IOS_DIR="."
else
    echo "note: check-hardcoded-api-urls: could not locate the ios/ directory, skipping"
    exit 0
fi

# The one file allowed to name the hosts: it *is* the environment switch.
ALLOWED="BittrAPIEnvironment.swift"

# Matches the API hosts only. Deliberately anchored on "https://" + exact host so
# that unrelated hits are not flagged: marketing links (getbittr.com/support),
# support@getbittr.com in user-facing copy, and the esplora subdomains
# (esplora.getbittr.com/api, esplora.regtest.getbittr.com/api) are all fine.
PATTERN='https://(staging\.)?getbittr\.com/api'

# `|| true` on both: grep exits 1 when there is nothing to report, which is the
# success case here, and `set -e` would otherwise abort the script.
MATCHES=$(
    grep -rnE --include='*.swift' "${PATTERN}" \
        "${IOS_DIR}/bittr" "${IOS_DIR}/BittrWidget" 2>/dev/null \
    | grep -v "/${ALLOWED}:" || true
)

if [ -n "${MATCHES}" ]; then
    echo "${MATCHES}" | while IFS= read -r line; do
        # "path:lineno:source" -> an Xcode-clickable "path:lineno: error: ..."
        path=$(echo "${line}" | cut -d: -f1)
        lineno=$(echo "${line}" | cut -d: -f2)
        echo "${path}:${lineno}: error: hard-coded bittr API URL. Build it from EnvironmentConfig.bittrAPIBaseURL (app) or BittrAPIEnvironment.baseURL (widget) instead — a literal sends DEBUG builds to production. See BIT-32."
    done
    exit 1
fi

echo "note: check-hardcoded-api-urls: no hard-coded bittr API URLs found"
exit 0
