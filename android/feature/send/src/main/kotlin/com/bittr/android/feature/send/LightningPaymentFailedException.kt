package com.bittr.android.feature.send

/**
 * A Lightning payment the network gave up on. [SendSource.payInvoice] fails with this, and
 * [SendController] leaves the explanation to the node's `paymentFailed` alert, as iOS does.
 */
class LightningPaymentFailedException : Exception("Payment failed")
