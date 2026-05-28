// Reads the MNEMONIC env var, splits it into 12 words, and stores them on
// output.words[1..12] (1-indexed, matching the pattern happy_path.yaml uses
// when it captures the words from the mnemonic display screen).
//
// MNEMONIC is passed by the caller, e.g.:
//
//   maestro test --env MNEMONIC="word1 word2 ... word12" \
//     shared/flows/features/forgot_pin.yaml
//
// or, easier, via shared/flows/scripts/run_forgot_pin.sh which reads the
// mnemonic from the booted simulator's UserDefaults.

if (typeof MNEMONIC === 'undefined' || !MNEMONIC) {
    throw new Error(
        'parse_mnemonic.js: MNEMONIC env var is not set. ' +
        'Run via shared/flows/scripts/run_forgot_pin.sh, or pass ' +
        '`maestro test --env MNEMONIC="<12 words>" ...` manually.'
    );
}

var parts = MNEMONIC.trim().split(/\s+/);
if (parts.length !== 12) {
    throw new Error(
        'parse_mnemonic.js: MNEMONIC must contain exactly 12 words, got ' +
        parts.length + '.'
    );
}

output.words = {};
for (var i = 0; i < 12; i++) {
    output.words[i + 1] = parts[i];
}
