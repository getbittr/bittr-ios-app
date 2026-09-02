// Builds output.notificationPayload for a fake Boltz swap-status push — the
// exact shape BitrecurExchange.AppleNotifications.send_boltz_notification emits,
// so the app's swap-notification path (handleSwapNotificationFromBackground)
// sees what production sends.
//
// With hashSwapId on, Boltz (and therefore bittr) only ever sees the SHA-256
// hash of the swap id, so output.swapIdHash must be that hash — the same value
// the app stores as Swap.swapIdHash. When the app receives a swap push it logs
// the ongoing swap's hash ("ongoing swap hash …, matches: …"), so you can copy
// it from the console after a first (mismatching) send and resend to get
// matches: true.
//
// Reads:  output.swapIdHash   (required — the hashed swap id)
//         output.swapStatus   (optional — defaults to "invoice.pending"; other
//                              real values: "transaction.lockupFailed",
//                              "invoice.settled")
// Writes: output.notificationPayload   (then call push_notification.js)

if (output.swapIdHash == null || output.swapIdHash === '') {
    throw new Error('build_swap_push.js: output.swapIdHash is not set');
}

var status = output.swapStatus != null ? output.swapStatus : 'invoice.pending';

output.notificationPayload = JSON.stringify({
    aps: {
        alert: { title: 'Your swap is ready for payout 💸', body: 'Open bittr to receive your satoshis!' },
        sound: 'default',
        'content-available': 1,
        'mutable-content': 1
    },
    swap_notification: {
        swap_id: output.swapIdHash,
        status: status
    }
});

console.log('built swap_notification push (swap_id=' + output.swapIdHash + ', status=' + status + ')');
