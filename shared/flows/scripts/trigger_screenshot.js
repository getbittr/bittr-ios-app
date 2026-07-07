// Asks the local screenshot_server.js helper to fire the Simulator's
// "Device > Trigger Screenshot", which posts userDidTakeScreenshotNotification —
// something Maestro's own takeScreenshot does not do. Use this when a flow needs
// the app to react to a real screenshot (e.g. the seed-phrase warning).
//
// Prerequisite (best-effort): the helper must be running —
//   node shared/flows/scripts/screenshot_server.js
// If it isn't reachable this logs and returns without throwing, so the calling
// flow can treat the resulting alert as optional and still pass.

try {
    var response = http.post(
        'http://localhost:8890/screenshot',
        { headers: { 'Content-Type': 'application/json' }, body: '{}' }
    );
    console.log('screenshot helper status: ' + response.status);
    console.log('screenshot helper body: ' + response.body);
    if (response.status < 200 || response.status >= 300) {
        console.log('screenshot helper returned an error — the seed-phrase warning may not fire.');
    }
} catch (e) {
    console.log('screenshot helper not reachable (skipping real screenshot trigger): ' + e);
}
