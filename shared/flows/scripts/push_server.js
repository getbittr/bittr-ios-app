#!/usr/bin/env node
// Local HTTP helper for Maestro flows — receives APNS payloads and forwards
// them to the booted iOS Simulator via `xcrun simctl push`.
//
// Maestro's GraalJS sandbox forbids Java interop, so JS scripts can't shell
// out directly. This server bridges the gap.
//
// Run once before testing:
//   node shared/flows/scripts/push_server.js
//
// Maestro flows POST to http://localhost:8888/push with the APNS JSON in
// the body. Bundle ID is fixed to com.bittr.bittr-regtest.

const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const PORT = 8888;
const BUNDLE_ID = 'com.bittr.bittr-regtest';

http.createServer((req, res) => {
    if (req.method !== 'POST' || req.url !== '/push') {
        res.writeHead(404);
        res.end('only POST /push is supported');
        return;
    }
    let body = '';
    req.on('data', (chunk) => { body += chunk; });
    req.on('end', () => {
        const tempPath = path.join(os.tmpdir(), `maestro-push-${Date.now()}.json`);
        try {
            fs.writeFileSync(tempPath, body);
            const result = spawnSync('xcrun', ['simctl', 'push', 'booted', BUNDLE_ID, tempPath]);
            const stdout = result.stdout?.toString() ?? '';
            const stderr = result.stderr?.toString() ?? '';
            if (result.status !== 0) {
                console.error('xcrun simctl push failed:', stderr);
                res.writeHead(500, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ ok: false, status: result.status, stderr }));
                return;
            }
            console.log(`pushed ${body.length}-byte payload to ${BUNDLE_ID}`);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ ok: true, stdout, stderr }));
        } catch (err) {
            console.error('handler error:', err);
            res.writeHead(500);
            res.end(String(err));
        } finally {
            fs.unlink(tempPath, () => {});
        }
    });
}).listen(PORT, '127.0.0.1', () => {
    console.log(`maestro push helper listening on http://127.0.0.1:${PORT}/push`);
    console.log(`forwarding to: xcrun simctl push booted ${BUNDLE_ID} <payload>`);
});
