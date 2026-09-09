// Puts text on the booted iOS Simulator's clipboard by relaying through the
// local clipboard_server.js helper (Maestro's JS sandbox blocks shelling out
// directly, and Maestro has no command to set the OS pasteboard itself).
//
// Prerequisite: run the helper in a separate terminal before the test:
//   node shared/flows/scripts/clipboard_server.js
//
// The calling flow sets output.clipboardText to the string to copy. See
// shared/flows/features/send_lightning.yaml for an example.

var text = output.clipboardText;
if (text == null || text === '') {
    throw new Error(
        'set_clipboard.js: output.clipboardText is empty. The flow must set ' +
        'it (usually from a --env value) before calling this script.'
    );
}

var response = http.post(
    'http://localhost:8889/clipboard',
    {
        headers: { 'Content-Type': 'text/plain' },
        body: text
    }
);

console.log('clipboard helper status: ' + response.status);
console.log('clipboard helper body: ' + response.body);

if (response.status < 200 || response.status >= 300) {
    throw new Error(
        'set_clipboard.js: helper returned ' + response.status + ' ' + response.body +
        '. Is clipboard_server.js running? `node shared/flows/scripts/clipboard_server.js`'
    );
}
