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

var response = http.post(
    'https://staging.getbittr.com/api/e2e/submit-invoice',
    {
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ invoice: invoice })
    }
);

console.log('e2e submit-invoice status: ' + response.status);
console.log('e2e submit-invoice body: ' + response.body);

if (response.status < 200 || response.status >= 300) {
    throw new Error('e2e submit-invoice failed: ' + response.status + ' ' + response.body);
}
