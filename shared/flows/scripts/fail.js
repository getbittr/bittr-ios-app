// Fails the flow with the message in output.failureMessage. Used by the
// EvilBoltz flows to fail LOUDLY with a precise diagnosis after demonstrating
// the vulnerability on an unfixed build — the failure is the signal, and the
// message must say exactly what was observed.

var message = output.failureMessage || 'fail.js: no failureMessage set';
console.log('FAILING FLOW: ' + message);
throw new Error(message);
