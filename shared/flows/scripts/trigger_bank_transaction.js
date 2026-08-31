// Posts an e2e bank-transaction event to the regtest backend, simulating
// SEPA money landing on the user's deposit code. The backend then pushes a
// Bittr notification that the iOS app surfaces via QuestionViewController.
//
// Reads the deposit code from output.depositCode (set by the calling flow
// after copyTextFrom on buy.yourCode). Optionally reads an amount in EUR
// from output.bankTransactionAmount; if unset, the backend uses its default.

var payload = { deposit_code: output.depositCode };
if (output.bankTransactionAmount != null) {
    payload.amount = output.bankTransactionAmount;
}

// The staging gateway occasionally answers with a transient 5xx (e.g. a 502
// while it redeploys); one blip must not kill a whole suite run. Retry with a
// linear busy-wait backoff (Maestro's JS sandbox has no sleep/import, so the
// helper is inlined — same pattern in the other staging-facing scripts). 4xx
// is NOT retried: the request itself is wrong and retrying can't fix it.
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
    'https://staging.getbittr.com/api/e2e/bank-transaction',
    {
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
    },
    'e2e bank-transaction'
);

console.log('e2e bank-transaction payload: ' + JSON.stringify(payload));
console.log('e2e bank-transaction status: ' + (response == null ? 'no response' : response.status));
console.log('e2e bank-transaction body: ' + (response == null ? '' : response.body));

if (response == null || response.status < 200 || response.status >= 300) {
    throw new Error('Bank transaction trigger failed after retries: ' + (response == null ? 'no response' : response.status + ' ' + response.body));
}

// Capture the fields the calling flow needs to fake the matching APNS push
// (see build_payout_push.js for how they're used).
//
// notification_id may be ABSENT — for a channel-open (first) deposit the
// backend hasn't created a notification record yet; the app completes those
// via an htlc_notification push + /htlc-interceptor/ready (deposit-code
// signed), which needs no notification id.
//
// bitcoin_amount must be present, and is STRINGIFIED here: the iOS app parses
// the push's bitcoin_amount AS A STRING (NotificationManager.toNotification:
// `bitcoin_amount as? String`), so a numeric e2e response field would make
// the app's payout guard fail with "Required data unavailable while trying
// to handle notification payout."
var data = JSON.parse(response.body);

if (data.notification_id != null) {
    output.notificationId = String(data.notification_id);
} else {
    output.notificationId = null;
    console.log('note: response has no notification_id — treating as channel-open deposit (htlc push)');
}

if (data.bitcoin_amount == null) {
    throw new Error(
        'e2e bank-transaction response is missing bitcoin_amount — ' +
        'the response shape may have changed. Body: ' + response.body
    );
}
output.bitcoinAmount = String(data.bitcoin_amount);
console.log('Captured notification_id=' + output.notificationId + ' bitcoin_amount=' + output.bitcoinAmount);
