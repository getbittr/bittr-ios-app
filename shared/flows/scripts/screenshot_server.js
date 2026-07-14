#!/usr/bin/env node
// Local HTTP helper for Maestro flows — on POST /screenshot it invokes the iOS
// Simulator's "Device > Trigger Screenshot" menu item via AppleScript.
//
// Why: `xcrun simctl io screenshot` and Maestro's own takeScreenshot only grab
// the framebuffer, so they do NOT post UIApplication.userDidTakeScreenshotNotification.
// The Simulator's "Trigger Screenshot" menu emulates the real screenshot gesture
// and DOES post it, so an app that reacts to screenshots (e.g. the seed-phrase
// "Be careful!" warning) fires. Maestro's GraalJS sandbox can't shell out, so —
// like push_server.js / clipboard_server.js — this server does it.
//
// Prerequisites:
//   - The Simulator is running.
//   - This process is allowed to control the computer via Accessibility:
//     System Settings > Privacy & Security > Accessibility → enable the terminal
//     app you run this from (System Events automation otherwise fails).
//   - The exact menu path can differ by Xcode version; adjust the AppleScript
//     below if the item isn't found (it matches any Device-menu item containing
//     "Screenshot").
//   - On the simulated device, turn OFF Settings > General > Screen Capture >
//     "Full-Screen Previews". Otherwise the screenshot preview covers the app
//     and never auto-dismisses, blocking flows that continue after the shot.
//
// Run once before testing:
//   node shared/flows/scripts/screenshot_server.js

const http = require('http');
const { spawnSync } = require('child_process');

const PORT = 8890;

// Activate the Simulator, then click the first "Device" menu item whose name
// contains "Screenshot" (e.g. "Trigger Screenshot").
const APPLESCRIPT = `
tell application "Simulator" to activate
delay 0.3
tell application "System Events"
  tell process "Simulator"
    set deviceMenu to menu "Device" of menu bar 1
    repeat with mi in menu items of deviceMenu
      try
        if name of mi contains "Screenshot" then
          click mi
          return "clicked: " & (name of mi)
        end if
      end try
    end repeat
    error "No Device-menu item containing 'Screenshot' was found"
  end tell
end tell
`;

http.createServer((req, res) => {
    if (req.method !== 'POST' || req.url !== '/screenshot') {
        res.writeHead(404);
        res.end('only POST /screenshot is supported');
        return;
    }
    const result = spawnSync('osascript', ['-e', APPLESCRIPT]);
    const stdout = result.stdout?.toString().trim() ?? '';
    const stderr = result.stderr?.toString().trim() ?? '';
    if (result.status !== 0) {
        console.error('osascript failed:', stderr);
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: false, stderr }));
        return;
    }
    console.log(`triggered simulator screenshot (${stdout})`);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true, stdout }));
}).listen(PORT, '127.0.0.1', () => {
    console.log(`maestro screenshot helper listening on http://127.0.0.1:${PORT}/screenshot`);
    console.log('forwarding to: osascript → Simulator "Device > Trigger Screenshot"');
});
