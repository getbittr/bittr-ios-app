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
 *
 * Encoded one pixel per module and drawn at a whole number of pixels per module, so the
 * bitmap is the code edge to edge. Asked for 1080 px straight away, ZXing fits the largest
 * whole module size into 1080 and centres the code in what is left over — up to a module's
 * width of extra white per module across, so the denser the code, the wider its white edge
 * and the smaller it read on screen. iOS scales its code to the full 1080 (`toBigQRCode`'s
 * `scale`), and the screen scales this bitmap to fill its box the same way.
 */
internal fun qrBitmap(payload: String, minSizePx: Int = QR_SIZE_PX): Bitmap {
    // Width and height 0: ZXing renders at the code's own size, one pixel per module.
    val matrix = QRCodeWriter().encode(
        payload,
        BarcodeFormat.QR_CODE,
        0,
        0,
        mapOf(
            EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.H,
            EncodeHintType.MARGIN to 0,
            EncodeHintType.CHARACTER_SET to "UTF-8",
        ),
    )
    val modules = matrix.width
    // Whole pixels per module, at least [minSizePx] across, so every module is the same size.
    val scale = (minSizePx + modules - 1) / modules
    val size = modules * scale
    val pixels = IntArray(size * size)
    for (y in 0 until size) {
        val row = y * size
        val moduleY = y / scale
        for (x in 0 until size) {
            pixels[row + x] = if (matrix[x / scale, moduleY]) Color.BLACK else Color.WHITE
        }
    }
    return Bitmap.createBitmap(pixels, size, size, Bitmap.Config.ARGB_8888)
}

/** `toBigQRCode`'s `targetSize`. */
private const val QR_SIZE_PX = 1080
