package com.bittr.android.feature.receive

import android.graphics.Bitmap
import android.graphics.Color
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel

/**
 * `String.toBigQRCode()` — a square black-on-white QR, error correction level H.
 *
 * Level H because iOS uses it (`String.swift:226`): it is what lets the logo sit over the
 * middle of the code and still scan. No quiet zone in the bitmap; the white box around it
 * on screen is the margin.
 */
internal fun qrBitmap(payload: String, sizePx: Int = QR_SIZE_PX): Bitmap {
    val matrix = QRCodeWriter().encode(
        payload,
        BarcodeFormat.QR_CODE,
        sizePx,
        sizePx,
        mapOf(
            EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.H,
            EncodeHintType.MARGIN to 0,
            EncodeHintType.CHARACTER_SET to "UTF-8",
        ),
    )
    val pixels = IntArray(matrix.width * matrix.height)
    for (y in 0 until matrix.height) {
        val row = y * matrix.width
        for (x in 0 until matrix.width) {
            pixels[row + x] = if (matrix[x, y]) Color.BLACK else Color.WHITE
        }
    }
    return Bitmap.createBitmap(pixels, matrix.width, matrix.height, Bitmap.Config.ARGB_8888)
}

/** `toBigQRCode`'s `targetSize`. */
private const val QR_SIZE_PX = 1080
