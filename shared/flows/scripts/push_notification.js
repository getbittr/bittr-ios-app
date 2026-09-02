// Sends a fake APNS push to the booted iOS Simulator by relaying through
// the local push_server.js helper (Maestro's JS sandbox blocks shelling out
// directly, so we can't call `xcrun simctl push` ourselves).
//
// Prerequisite: run the helper in a separate terminal before the test:
//   node shared/flows/scripts/push_server.js
//
// The calling flow sets output.notificationPayload to a JSON string. See
// shared/flows/features/buy_more.yaml for an example.

var payload = output.notificationPayload;
if (payload == null) {
    throw new Error('push_notification.js: output.notificationPayload is not set');
}

// Default target is the regtest app; callers may set output.pushBundleId
// (e.g. the EvilBoltz flows target com.bittr.bittr-evil).
var url = 'http://localhost:8888/push';
if (output.pushBundleId != null) {
    url += '?bundleId=' + encodeURIComponent(output.pushBundleId);
}

var response = http.post(
    url,
    {
        headers: { 'Content-Type': 'application/json' },
        body: payload
    }
);

console.log('push helper status: ' + response.status);
console.log('push helper body: ' + response.body);

if (response.status < 200 || response.status >= 300) {
    throw new Error(
        'push_notification.js: helper returned ' + response.status + ' ' + response.body +
        '. Is push_server.js running? `node shared/flows/scripts/push_server.js`'
    );
}
