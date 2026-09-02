// Builds output.notificationPayload for a fake payout push, choosing the push
// TYPE from what the e2e bank-transaction response contained:
//
//   • notification_id present (regular payout, channel already open):
//     a bittr_specific_data lightning payout — the buy_more.yaml shape. The
//     app's payout guard (facilitateNotificationPayout) requires
//     notification_id AND bitcoin_amount here, both captured by
//     trigger_bank_transaction.js.
//
//   • notification_id absent (channel-open / first deposit): an
//     htlc_notification — the notification_htlcincoming.yaml shape. The app
//     reads the deposit code from the wallet and calls /htlc-interceptor/ready
//     (facilitateHTLCReady); no notification id is involved. An empty object
//     is enough (no "expired" flag → .htlcIncoming).
//
// Reads:  output.notificationId, output.bitcoinAmount
// Writes: output.notificationPayload   (then call push_notification.js)

if (output.notificationId != null) {
    output.notificationPayload = JSON.stringify({
        aps: { alert: { title: 'Bitcoin received', body: '+ sats from bittr' }, sound: 'default' },
        bittr_specific_data: {
            notification_id: output.notificationId,
            bitcoin_amount: output.bitcoinAmount
        }
    });
    console.log('built lightningPayout push (notification_id=' + output.notificationId + ')');
} else {
    output.notificationPayload = JSON.stringify({
        aps: { alert: { title: 'Incoming payment', body: "You're receiving a payment." }, sound: 'default' },
        htlc_notification: {}
    });
    console.log('built htlcIncoming push (channel-open deposit)');
}
