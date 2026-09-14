#!/usr/bin/env node
// Local HTTP helper for Maestro flows — receives APNS payloads and forwards
// them to the app under test: the booted iOS Simulator via `xcrun simctl push`,
// or an Android emulator via `adb shell am broadcast`.
//
// Maestro's GraalJS sandbox forbids Java interop, so JS scripts can't shell
// out directly. This server bridges the gap.
//
// Run once before testing:
//   node shared/flows/scripts/push_server.js                              # iOS
//   BITTR_PUSH_PLATFORM=android node shared/flows/scripts/push_server.js  # Android
//
// Maestro flows POST to http://localhost:8888/push with the APNS JSON in
// the body. Bundle ID defaults to com.bittr.bittr-regtest; override it
// per request with ?bundleId=... (e.g. com.bittr.bittr-evil for the
// EvilBoltz test app) or process-wide via BITTR_PUSH_BUNDLE_ID.
//
// Android mode (BITTR_PUSH_PLATFORM=android, or ?platform=android): the same
// APNS JSON is turned into the FCM data map the app decodes — each bittr key
// (bittr_specific_data, bittr_notification, swap_notification,
// htlc_notification, lightning_address_notification) becomes a string extra
// holding its JSON, and `aps` is dropped — and sent to the debug-only
// DebugPushReceiver:
//   adb shell am broadcast -a com.bittr.android.DEBUG_PUSH -p <package> --es <key> '<json>'
// The package defaults to com.bittr.android.regtest (BITTR_PUSH_ANDROID_PACKAGE);
// set ANDROID_SERIAL to pick an emulator when more than one is attached.

const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const PORT = 8888;
const DEFAULT_BUNDLE_ID = process.env.BITTR_PUSH_BUNDLE_ID || 'com.bittr.bittr-regtest';
const DEFAULT_PLATFORM = (process.env.BITTR_PUSH_PLATFORM || 'ios').toLowerCase();
const ANDROID_PACKAGE = process.env.BITTR_PUSH_ANDROID_PACKAGE || 'com.bittr.android.regtest';
const ANDROID_ACTION = 'com.bittr.android.DEBUG_PUSH';
const BITTR_KEYS = [
    'bittr_specific_data',
    'bittr_notification',
    'swap_notification',
    'htlc_notification',
    'lightning_address_notification',
];

// One argument for the device shell: `adb shell` joins its arguments with spaces
// and hands them to sh, so each value is single-quoted there.
function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'";
}

function pushIos(body, bundleId) {
    const tempPath = path.join(os.tmpdir(), `maestro-push-${Date.now()}.json`);
    try {
        fs.writeFileSync(tempPath, body);
        return spawnSync('xcrun', ['simctl', 'push', 'booted', bundleId, tempPath]);
    } finally {
        fs.unlink(tempPath, () => {});
    }
}

function pushAndroid(body, androidPackage) {
    const payload = JSON.parse(body);
    const args = ['shell', 'am', 'broadcast', '-a', ANDROID_ACTION, '-p', androidPackage];
    for (const key of BITTR_KEYS) {
        if (payload[key] === undefined) continue;
        // FCM data values are strings; the app parses the JSON inside.
        args.push('--es', key, shellQuote(JSON.stringify(payload[key])));
    }
    return spawnSync('adb', args);
}

http.createServer((req, res) => {
    const requestUrl = new URL(req.url, 'http://localhost');
    if (req.method !== 'POST' || requestUrl.pathname !== '/push') {
        res.writeHead(404);
        res.end('only POST /push is supported');
        return;
    }
    const bundleId = requestUrl.searchParams.get('bundleId') || DEFAULT_BUNDLE_ID;
    const platform = (requestUrl.searchParams.get('platform') || DEFAULT_PLATFORM).toLowerCase();
    let body = '';
    req.on('data', (chunk) => { body += chunk; });
    req.on('end', () => {
        try {
            const android = platform === 'android';
            const target = android ? (requestUrl.searchParams.get('bundleId') || ANDROID_PACKAGE) : bundleId;
            const result = android ? pushAndroid(body, target) : pushIos(body, target);
            const stdout = result.stdout?.toString() ?? '';
            const stderr = result.stderr?.toString() ?? '';
            if (result.status !== 0) {
                console.error(`${android ? 'adb am broadcast' : 'xcrun simctl push'} failed:`, stderr);
                res.writeHead(500, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ ok: false, status: result.status, stderr }));
                return;
            }
            console.log(`pushed ${body.length}-byte payload to ${target} (${platform})`);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ ok: true, stdout, stderr }));
        } catch (err) {
            console.error('handler error:', err);
            res.writeHead(500);
            res.end(String(err));
        }
    });
}).listen(PORT, '127.0.0.1', () => {
    console.log(`maestro push helper listening on http://127.0.0.1:${PORT}/push`);
    if (DEFAULT_PLATFORM === 'android') {
        console.log(`forwarding to: adb shell am broadcast -a ${ANDROID_ACTION} -p ${ANDROID_PACKAGE} (override per request with ?bundleId=...)`);
    } else {
        console.log(`forwarding to: xcrun simctl push booted ${DEFAULT_BUNDLE_ID} <payload> (override per request with ?bundleId=...)`);
    }
});
