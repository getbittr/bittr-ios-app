package com.bittr.android.feature.receive

import android.graphics.Bitmap
import android.graphics.Color
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import kotlin.math.ceil

/**
 * A QR code edge to edge, and the white box for the logo over its middle, as a share of its width.
 *
 * @property logoBox the box's width: whole modules, odd or even like the code itself, so it centres
 * on the module grid and its edges fall on module edges.
 * @property logoMark the logo's width inside the box, which leaves it 30 px of the 1080 all round.
 */
internal class QrCode(val bitmap: Bitmap, val logoBox: Float, val logoMark: Float)

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
internal fun qrCode(payload: String, minSizePx: Int = QR_SIZE_PX): QrCode {
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
    val bitmap = Bitmap.createBitmap(pixels, size, size, Bitmap.Config.ARGB_8888)

    val boxPx = logoModules(modules) * scale
    return QrCode(
        bitmap = bitmap,
        logoBox = boxPx.toFloat() / size,
        logoMark = (boxPx - 2 * LOGO_PADDING_PX).toFloat() / boxPx,
    )
}

/**
 * How many modules wide the logo's box is in a code [modules] wide: about 13 % of the width, rounded up
 * to whole modules and to the code's parity, so it centres on the grid.
 */
internal fun logoModules(modules: Int): Int {
    val atLeast = ceil(modules * LOGO_SHARE).toInt()
    return if (atLeast % 2 == modules % 2) atLeast else atLeast + 1
}

/** `toBigQRCode`'s `targetSize`. */
private const val QR_SIZE_PX = 1080

/** `toBigQRCode`'s `0.13`. */
private const val LOGO_SHARE = 0.13

/** `toBigQRCode`'s `padding`. */
private const val LOGO_PADDING_PX = 30
