// Resolves the LNURL-pay parameters for a Lightning Address so a flow can build
// a realistic .lnUrl notification payload. Reads the address from
// output.lnurlAddress (default the e2e e2ebittr@staging.getbittr.com — the same
// address send_lightning.yaml pays), GETs its /.well-known/lnurlp/<user>, and
// puts the metadata + username on output. Falls back to a static metadata if
// resolution fails so the flow stays runnable offline.
//
// NOTE: the LNURL-pay params give us metadata / callback / username, but NOT the
// per-request "endpoint" the app POSTs its generated invoice back to — that URL
// is minted by the bittr backend when a payer initiates a payment, so the
// notification flow has to supply its own endpoint.

var address = output.lnurlAddress || 'e2ebittr@staging.getbittr.com';
var at = address.indexOf('@');
var user = address.substring(0, at);
var host = address.substring(at + 1);

output.lnurlUsername = user;

try {
    var res = http.get('https://' + host + '/.well-known/lnurlp/' + user);
    console.log('lnurlp status: ' + res.status);
    if (res.status >= 200 && res.status < 300) {
        var data = JSON.parse(res.body);
        if (data.metadata != null) { output.lnurlMetadata = data.metadata; }
        if (data.callback != null) { output.lnurlCallback = data.callback; }
    }
} catch (e) {
    console.log('LNURL resolve failed: ' + e);
}

if (output.lnurlMetadata == null) {
    console.log('Falling back to static LNURL metadata.');
    output.lnurlMetadata = '[["text/plain","Pay e2ebittr via bittr"]]';
}

console.log('LNURL metadata: ' + output.lnurlMetadata);
