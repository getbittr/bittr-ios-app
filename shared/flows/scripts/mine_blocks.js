// Mines blocks on the regtest backend via the e2e endpoint.
//
// Reads the block count from output.blocksToMine, which the calling flow must
// set before invoking this script:
//
//   - evalScript: ${output.blocksToMine = 6}   # channel-open confirmation
//   - runScript: ../scripts/mine_blocks.js
//
// 6 blocks confirms a lightning channel; 1 is usually enough for plain
// onchain confirmation paths.

var blocks = output.blocksToMine;

if (blocks == null) {
    throw new Error('mine_blocks.js: output.blocksToMine is not set');
}

// Retry transient 5xx / network errors with linear busy-wait backoff so one
// staging-gateway blip doesn't kill a whole suite run (mining a few extra
// blocks on a retry after an ambiguous failure is harmless on regtest). 4xx is
// not retried. Inlined per script — Maestro's JS sandbox has no sleep/import.
function postWithRetry(url, options, label) {
    var attempts = 5;
    var response = null;
    for (var i = 1; i <= attempts; i++) {
        try {
            response = http.post(url, options);
        } catch (e) {
            response = null;
            console.log(label + ' attempt ' + i + '/' + attempts + ' network error: ' + e);
        }
        if (response != null && response.status < 500) {
            return response;
        }
        if (response != null) {
            console.log(label + ' attempt ' + i + '/' + attempts + ' got ' + response.status + ' — retrying');
        }
        if (i < attempts) {
            var waitMs = 3000 * i;
            var start = Date.now();
            while (Date.now() - start < waitMs) { /* spin */ }
        }
    }
    return response;
}

var response = postWithRetry(
    'https://staging.getbittr.com/api/e2e/mine-blocks',
    {
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ blocks: blocks })
    },
    'e2e mine-blocks'
);

console.log('e2e mine-blocks (' + blocks + ') status: ' + (response == null ? 'no response' : response.status));
console.log('e2e mine-blocks body: ' + (response == null ? '' : response.body));

if (response == null || response.status < 200 || response.status >= 300) {
    throw new Error('Mine blocks trigger failed after retries: ' + (response == null ? 'no response' : response.status + ' ' + response.body));
}
