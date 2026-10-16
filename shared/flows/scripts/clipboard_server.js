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
// the Mac clipboard holds whatever the flows paste.
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

function run(command, args, input) {
    const result = spawnSync(command, args, { input });
    return {
        ok: result.status === 0,
        status: result.status,
        stdout: result.stdout?.toString() ?? '',
        stderr: result.stderr?.toString() ?? ''
    };
}

function readSimulatorClipboard() {
    return run('xcrun', ['simctl', 'pbpaste', 'booted']).stdout;
}

async function waitForSimulatorClipboard(text) {
    // Polls until the simulator's clipboard holds the text, or the timeout passes.
    const deadline = Date.now() + VERIFY_TIMEOUT_MS;
    while (true) {
        const current = readSimulatorClipboard();
        if (current === text) return { ok: true, current };
        if (Date.now() >= deadline) return { ok: false, current };
        await new Promise((resolve) => setTimeout(resolve, VERIFY_INTERVAL_MS));
    }
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
            // The Mac's clipboard reaches the simulator through Simulator's pasteboard sync.
            const mac = run('pbcopy', [], body);
            if (!mac.ok) {
                console.error('pbcopy failed:', mac.stderr);
                respond(res, 500, { ok: false, step: 'pbcopy', status: mac.status, stderr: mac.stderr });
                return;
            }

            // `xcrun simctl pbcopy booted` reads the clipboard contents from stdin.
            // It covers setups with the pasteboard sync turned off.
            const simulator = run('xcrun', ['simctl', 'pbcopy', 'booted'], body);
            if (!simulator.ok) {
                console.error('xcrun simctl pbcopy failed:', simulator.stderr);
                respond(res, 500, { ok: false, step: 'simctl pbcopy', status: simulator.status, stderr: simulator.stderr });
                return;
            }

            // Confirm the app will actually paste this text, so a failed copy fails here.
            const verified = await waitForSimulatorClipboard(body);
            if (!verified.ok) {
                const found = verified.current.slice(0, 80);
                console.error(`simulator clipboard doesn't hold the text after ${VERIFY_TIMEOUT_MS}ms; found: ${JSON.stringify(found)}`);
                respond(res, 500, { ok: false, step: 'verify', found, stderr: simulator.stderr });
                return;
            }

            console.log(`copied ${body.length}-byte string to the Mac and booted simulator clipboards`);
            respond(res, 200, { ok: true, stderr: simulator.stderr });
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
