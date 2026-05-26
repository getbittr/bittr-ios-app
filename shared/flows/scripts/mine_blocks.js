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

var response = http.post(
    'https://staging.getbittr.com/api/e2e/mine-blocks',
    {
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ blocks: blocks })
    }
);

console.log('e2e mine-blocks (' + blocks + ') status: ' + response.status);
console.log('e2e mine-blocks body: ' + response.body);

if (response.status < 200 || response.status >= 300) {
    throw new Error('Mine blocks trigger failed: ' + response.status + ' ' + response.body);
}
