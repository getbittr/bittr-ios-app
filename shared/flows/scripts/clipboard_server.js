#!/usr/bin/env node
// Local HTTP helper for Maestro flows — receives text and writes it to the
// device clipboard: the booted iOS Simulator via `xcrun simctl pbcopy`, or an
// Android emulator via the debug build's DebugClipboardReceiver.
//
// Maestro's GraalJS sandbox forbids Java interop, so JS scripts can't shell
// out directly, and Maestro has no command to set the device clipboard (its
// `copyTextFrom` only fills Maestro's own `maestro.copiedText` variable, not
// the OS pasteboard). This server bridges the gap so flows can exercise the
// real in-app "Paste" button. Mirrors push_server.js.
//
// Run once before testing:
//   node shared/flows/scripts/clipboard_server.js                                  # iOS
//   BITTR_CLIPBOARD_PLATFORM=android node shared/flows/scripts/clipboard_server.js # Android
//
// Maestro flows POST the text to put on the clipboard to
// http://localhost:8889/clipboard with the raw text in the body.
// GET http://localhost:8889/clipboard returns what is on the clipboard now.
//
// Android mode: `adb shell` may not use the clipboard on modern Android, so the
// text goes to the debug-only receiver in the app, base64-encoded:
//   adb shell am broadcast -a com.bittr.android.DEBUG_CLIPBOARD_SET -p <package> --es text_b64 <base64>
// The package defaults to com.bittr.android.regtest (BITTR_CLIPBOARD_ANDROID_PACKAGE);
// set ANDROID_SERIAL to pick a device when more than one is attached.

const http = require('http');
const { spawnSync } = require('child_process');

const PORT = 8889;
const PLATFORM = (process.env.BITTR_CLIPBOARD_PLATFORM || process.env.BITTR_PUSH_PLATFORM || 'ios').toLowerCase();
const ANDROID_PACKAGE = process.env.BITTR_CLIPBOARD_ANDROID_PACKAGE || 'com.bittr.android.regtest';

function setIos(text) {
    // `xcrun simctl pbcopy booted` reads the clipboard contents from stdin.
    const result = spawnSync('xcrun', ['simctl', 'pbcopy', 'booted'], { input: text });
    return { ok: result.status === 0, status: result.status, stderr: result.stderr?.toString() ?? '' };
}

function getIos() {
    const result = spawnSync('xcrun', ['simctl', 'pbpaste', 'booted']);
    return { ok: result.status === 0, text: result.stdout?.toString() ?? '', stderr: result.stderr?.toString() ?? '' };
}

function broadcastAndroid(action, extraArgs) {
    const args = ['shell', 'am', 'broadcast', '-a', action, '-p', ANDROID_PACKAGE, ...extraArgs];
    const result = spawnSync('adb', args);
    const stdout = result.stdout?.toString() ?? '';
    // `am broadcast` prints e.g. `Broadcast completed: result=-1, data="aGVsbG8="`.
    const data = /data="([^"]*)"/.exec(stdout);
    return {
        ok: result.status === 0 && /result=-1/.test(stdout),
        status: result.status,
        data: data ? data[1] : null,
        stderr: (result.stderr?.toString() ?? '') + (result.status === 0 ? '' : stdout),
    };
}

function setAndroid(text) {
    const encoded = Buffer.from(text, 'utf8').toString('base64');
    return broadcastAndroid('com.bittr.android.DEBUG_CLIPBOARD_SET', ['--es', 'text_b64', encoded]);
}

function getAndroid() {
    const result = broadcastAndroid('com.bittr.android.DEBUG_CLIPBOARD_GET', []);
    return { ...result, text: result.data == null ? '' : Buffer.from(result.data, 'base64').toString('utf8') };
}

http.createServer((req, res) => {
    if (req.url !== '/clipboard' || (req.method !== 'POST' && req.method !== 'GET')) {
        res.writeHead(404);
        res.end('only POST /clipboard and GET /clipboard are supported');
        return;
    }
    if (req.method === 'GET') {
        const result = PLATFORM === 'android' ? getAndroid() : getIos();
        res.writeHead(result.ok ? 200 : 500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: result.ok, text: result.text, stderr: result.stderr }));
        return;
    }
    let body = '';
    req.on('data', (chunk) => { body += chunk; });
    req.on('end', () => {
        try {
            const result = PLATFORM === 'android' ? setAndroid(body) : setIos(body);
            if (!result.ok) {
                console.error(`setting the ${PLATFORM} clipboard failed:`, result.stderr);
                res.writeHead(500, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ ok: false, status: result.status, stderr: result.stderr }));
                return;
            }
            console.log(`copied ${body.length}-byte string to the ${PLATFORM} clipboard`);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ ok: true, stderr: result.stderr }));
        } catch (err) {
            console.error('handler error:', err);
            res.writeHead(500);
            res.end(String(err));
        }
    });
}).listen(PORT, '127.0.0.1', () => {
    console.log(`maestro clipboard helper listening on http://127.0.0.1:${PORT}/clipboard`);
    console.log(PLATFORM === 'android'
        ? `forwarding to: adb shell am broadcast -a com.bittr.android.DEBUG_CLIPBOARD_SET -p ${ANDROID_PACKAGE}`
        : 'forwarding to: xcrun simctl pbcopy booted <text>');
});
