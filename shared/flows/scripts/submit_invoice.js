// Pays a lightning invoice via the bittr e2e endpoint, so a flow can verify
// the app's incoming-payment handling end to end (the regtest backend node
// pays the invoice the app just generated). Mirrors trigger_bank_transaction.js.
//
// The calling flow captures the bolt11 first (copyTextFrom the invoice label,
// then stash it on output.invoice) and then runs this script:
//
//   - copyTextFrom: { id: "receive.invoiceLabel" }
//   - evalScript: ${output.invoice = maestro.copiedText}
//   - runScript: ../scripts/submit_invoice.js

var invoice = output.invoice;

if (invoice == null || invoice === '') {
    throw new Error('submit_invoice.js: output.invoice is not set');
}

// bolt11 invoices are a single token — strip any whitespace the label may have
// introduced when its text was copied.
invoice = invoice.replace(/\s/g, '');

// Retry transient 5xx / network errors with linear busy-wait backoff so one
// staging-gateway blip doesn't kill a whole suite run. Retrying a payment is
// safe: a bolt11 invoice settles at most once (same payment hash), so if an
// ambiguous 5xx actually paid it, the retry just reports already-paid. 4xx is
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
    'https://staging.getbittr.com/api/e2e/submit-invoice',
    {
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ invoice: invoice })
    },
    'e2e submit-invoice'
);

console.log('e2e submit-invoice status: ' + (response == null ? 'no response' : response.status));
console.log('e2e submit-invoice body: ' + (response == null ? '' : response.body));

if (response == null || response.status < 200 || response.status >= 300) {
    throw new Error('e2e submit-invoice failed after retries: ' + (response == null ? 'no response' : response.status + ' ' + response.body));
}
