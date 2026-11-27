#!/usr/bin/env node
// Local HTTP helper for Maestro flows — receives text and puts it on the
// booted iOS Simulator's clipboard.
//
// Maestro's GraalJS sandbox forbids Java interop, so JS scripts can't shell
// out directly, and Maestro has no command to set the device clipboard (its
// `copyTextFrom` only fills Maestro's own `maestro.copiedText` variable, not
// the OS pasteboard). This server bridges the gap so flows can exercise the
// real in-app "Paste" button. Mirrors push_server.js.
//
// The text goes on the Mac's clipboard too. With Simulator's "Automatically
// Sync Pasteboard" on, the simulator mirrors the Mac's clipboard, and on
// Xcode 27 `xcrun simctl pbcopy` alone leaves it unchanged. So during a run,
// the Mac clipboard holds whatever the flows paste. When the helper stops, the
// Mac clipboard gets back the text it held before, unless it was copied over.
//
// Run once before testing:
//   node shared/flows/scripts/clipboard_server.js
//
// Maestro flows POST the text to put on the clipboard to
// http://localhost:8889/clipboard with the raw text in the body.

const http = require('http');
const { spawnSync } = require('child_process');

const PORT = 8889;

// How long to wait for the simulator's clipboard to show the text.
const VERIFY_TIMEOUT_MS = 2000;
const VERIFY_INTERVAL_MS = 100;

let savedMacClipboard = null;
let lastCopiedText = null;

function run(command, args, input) {
    const result = spawnSync(command, args, { input });
    return {
        ok: result.status === 0,
        status: result.status,
        stdout: result.stdout?.toString() ?? '',
        stderr: result.error?.message ?? result.stderr?.toString() ?? ''
    };
}

async function setIos(text) {
    if (savedMacClipboard === null) {
        const before = run('pbpaste', []);
        if (before.ok) savedMacClipboard = before.stdout;
    }

    // The Mac's clipboard reaches the simulator through Simulator's pasteboard sync.
    const mac = run('pbcopy', [], text);
    if (mac.ok) lastCopiedText = text;
    else console.warn('pbcopy failed, relying on simctl pbcopy:', mac.stderr);

    // `xcrun simctl pbcopy booted` reads the clipboard contents from stdin.
    // It covers setups with the pasteboard sync turned off.
    const simulator = run('xcrun', ['simctl', 'pbcopy', 'booted'], text);
    if (!simulator.ok) return { ok: false, step: 'simctl pbcopy', status: simulator.status, stderr: simulator.stderr };

    // Confirm the app will actually paste this text, so a failed copy fails here.
    const deadline = Date.now() + VERIFY_TIMEOUT_MS;
    while (true) {
        const current = getIos();
        if (!current.ok) return { ok: false, step: 'simctl pbpaste', status: current.status, stderr: current.stderr };
        if (current.text === text) return { ok: true, stderr: simulator.stderr };
        if (Date.now() >= deadline) return { ok: false, step: 'verify', found: current.text.slice(0, 80), stderr: simulator.stderr, macStderr: mac.ok ? undefined : mac.stderr };
        await new Promise((resolve) => setTimeout(resolve, VERIFY_INTERVAL_MS));
    }
}

function getIos() {
    const result = run('xcrun', ['simctl', 'pbpaste', 'booted']);
    return { ok: result.ok, status: result.status, text: result.stdout, stderr: result.stderr };
}

function restoreMacClipboard() {
    if (savedMacClipboard === null || run('pbpaste', []).stdout !== lastCopiedText) return;
    run('pbcopy', [], savedMacClipboard);
    console.log('gave the Mac clipboard back its earlier text');
}

for (const signal of ['SIGINT', 'SIGTERM']) {
    process.on(signal, () => {
        restoreMacClipboard();
        process.exit(0);
    });
}

function respond(res, status, body) {
    res.writeHead(status, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(body));
}

http.createServer((req, res) => {
    if (req.method !== 'POST' || req.url !== '/clipboard') {
        res.writeHead(404);
        res.end('only POST /clipboard is supported');
        return;
    }
    let body = '';
    req.on('data', (chunk) => { body += chunk; });
    req.on('end', async () => {
        try {
            const result = await setIos(body);
            if (!result.ok) {
                const detail = result.step === 'verify'
                    ? `clipboard doesn't hold the text after ${VERIFY_TIMEOUT_MS}ms; found: ${JSON.stringify(result.found)}${result.macStderr === undefined ? '' : `; pbcopy failed: ${result.macStderr}`}`
                    : result.stderr;
                console.error(`setting the iOS clipboard failed at ${result.step}:`, detail);
                if (result.step === 'verify') console.error('restarting the simulator (Device → Restart) usually fixes this');
                respond(res, 500, result);
                return;
            }
            console.log(`copied ${body.length}-byte string to the Mac and booted simulator clipboards`);
            respond(res, 200, { ok: true, stderr: result.stderr });
        } catch (err) {
            console.error('handler error:', err);
            res.writeHead(500);
            res.end(String(err));
        }
    });
}).listen(PORT, '127.0.0.1', () => {
    console.log(`maestro clipboard helper listening on http://127.0.0.1:${PORT}/clipboard`);
    console.log('forwarding to: pbcopy and xcrun simctl pbcopy booted, then verifying with xcrun simctl pbpaste booted');
});
