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

var response = http.post(
    'https://staging.getbittr.com/api/e2e/bank-transaction',
    {
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
    }
);

console.log('e2e bank-transaction payload: ' + JSON.stringify(payload));
console.log('e2e bank-transaction status: ' + response.status);
console.log('e2e bank-transaction body: ' + response.body);

if (response.status < 200 || response.status >= 300) {
    throw new Error('Bank transaction trigger failed: ' + response.status + ' ' + response.body);
}

// Capture the fields the calling flow needs to fake the matching APNS push
// (notification_id + bitcoin_amount go into bittr_specific_data).
var data = JSON.parse(response.body);
output.notificationId = data.notification_id;
output.bitcoinAmount = data.bitcoin_amount;
console.log('Captured notification_id=' + output.notificationId + ' bitcoin_amount=' + output.bitcoinAmount);
