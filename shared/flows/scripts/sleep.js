// Busy-waits for output.sleepMs milliseconds (default 2000). Maestro has no
// native sleep, and a few flows need a fixed pause to let the app do background
// work between steps — e.g. to let a push be handled BEFORE the next action.
// The wait runs on the host JS side, so the app under test keeps running (and
// keeps processing the push) while we wait.
//
// The calling flow sets the duration first:
//   - evalScript: ${output.sleepMs = 2500}
//   - runScript: ../scripts/sleep.js

var ms = (output.sleepMs != null) ? output.sleepMs : 2000;
var start = Date.now();
while (Date.now() - start < ms) { /* spin */ }
console.log('slept ' + ms + 'ms');
