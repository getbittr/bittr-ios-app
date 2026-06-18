#!/usr/bin/env node
// Local HTTP helper for Maestro flows — receives text and writes it to the
// booted iOS Simulator's clipboard via `xcrun simctl pbcopy`.
//
// Maestro's GraalJS sandbox forbids Java interop, so JS scripts can't shell
// out directly, and Maestro has no command to set the device clipboard (its
// `copyTextFrom` only fills Maestro's own `maestro.copiedText` variable, not
// the OS pasteboard). This server bridges the gap so flows can exercise the
// real in-app "Paste" button. Mirrors push_server.js.
//
// Run once before testing:
//   node shared/flows/scripts/clipboard_server.js
//
// Maestro flows POST the text to put on the clipboard to
// http://localhost:8889/clipboard with the raw text in the body.

const http = require('http');
const { spawnSync } = require('child_process');

const PORT = 8889;

http.createServer((req, res) => {
    if (req.method !== 'POST' || req.url !== '/clipboard') {
        res.writeHead(404);
        res.end('only POST /clipboard is supported');
        return;
    }
    let body = '';
    req.on('data', (chunk) => { body += chunk; });
    req.on('end', () => {
        try {
            // `xcrun simctl pbcopy booted` reads the clipboard contents from stdin.
            const result = spawnSync('xcrun', ['simctl', 'pbcopy', 'booted'], { input: body });
            const stderr = result.stderr?.toString() ?? '';
            if (result.status !== 0) {
                console.error('xcrun simctl pbcopy failed:', stderr);
                res.writeHead(500, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ ok: false, status: result.status, stderr }));
                return;
            }
            console.log(`copied ${body.length}-byte string to the booted simulator clipboard`);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ ok: true, stderr }));
        } catch (err) {
            console.error('handler error:', err);
            res.writeHead(500);
            res.end(String(err));
        }
    });
}).listen(PORT, '127.0.0.1', () => {
    console.log(`maestro clipboard helper listening on http://127.0.0.1:${PORT}/clipboard`);
    console.log('forwarding to: xcrun simctl pbcopy booted <text>');
});
