// Requests a fresh lightning invoice from the bittr e2e endpoint, so flows
// don't have to be handed a (quickly-expiring) invoice via --env. Mirrors
// mine_blocks.js. Generating it server-side per run also avoids stale-invoice
// flakiness.
//
// The calling flow sets the amount in satoshis first (0 = a zero-amount
// invoice), then this script puts the bolt11 on both output.invoice and
// output.clipboardText (ready to hand straight to set_clipboard.js):
//
//   - evalScript: ${output.invoiceAmountSats = 1000}   # 0 for zero-amount
//   - runScript: ../scripts/request_invoice.js
//   - runScript: ../scripts/set_clipboard.js
//
// NOTE: confirm the path matches the deployed endpoint — mine_blocks.js uses
// the /api/e2e/ prefix, so this assumes /api/e2e/invoice.

var amount = output.invoiceAmountSats;

if (amount == null) {
    throw new Error('request_invoice.js: output.invoiceAmountSats is not set');
}

// Retry transient 5xx / network errors with linear busy-wait backoff so one
// staging-gateway blip doesn't kill a whole suite run (requesting an extra
// invoice on retry is harmless — the older one just goes unused). 4xx is not
// retried. Inlined per script — Maestro's JS sandbox has no sleep/import.
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
    'https://staging.getbittr.com/api/e2e/invoice',
    {
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ amount_in_sats: amount, memo: 'E2E test' })
    },
    'e2e invoice'
);

console.log('e2e invoice (' + amount + ' sats) status: ' + (response == null ? 'no response' : response.status));
console.log('e2e invoice body: ' + (response == null ? '' : response.body));

if (response == null || response.status < 200 || response.status >= 300) {
    throw new Error('e2e invoice request failed after retries: ' + (response == null ? 'no response' : response.status + ' ' + response.body));
}

var data = JSON.parse(response.body);

// Accept whichever field the endpoint uses for the bolt11 string (top-level or
// nested under `data`). Adjust here if the endpoint uses a different key.
var invoice =
    data.invoice || data.bolt11 || data.payment_request || data.pr ||
    (data.data && (data.data.invoice || data.data.bolt11 || data.data.payment_request));

if (invoice == null || invoice === '') {
    throw new Error('request_invoice.js: no bolt11 field found in response: ' + response.body);
}

output.invoice = invoice;
output.clipboardText = invoice;
