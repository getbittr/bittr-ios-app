package com.bittr.android.feature.scanner

import com.google.zxing.BinaryBitmap
import com.google.zxing.ChecksumException
import com.google.zxing.DecodeHintType
import com.google.zxing.FormatException
import com.google.zxing.NotFoundException
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.qrcode.QRCodeReader

/**
 * One camera frame, reduced to the only thing a QR reader needs: brightness.
 *
 * [data] is the Y plane of a YUV_420_888 image — one byte of luminance per pixel,
 * colour discarded. Rows are [rowStride] bytes apart, which is **not** always
 * [width]: the camera hardware pads each row out to an alignment it likes, so
 * treating the buffer as tightly packed shears the image diagonally and nothing
 * decodes.
 *
 * The frame does not outlive the decode. It is built from a buffer the camera lends
 * us for the duration of one analyser callback, read once, and dropped — see
 * [QrAnalyzer].
 */
internal data class LuminanceFrame(
    val data: ByteArray,
    val width: Int,
    val height: Int,
    val rowStride: Int = width,
) {
    // ByteArray gets identity equals/hashCode, which would make the generated ones
    // wrong in a way that only shows up in a test. Compare what the frame means.
    override fun equals(other: Any?): Boolean =
        this === other || (
            other is LuminanceFrame &&
                width == other.width &&
                height == other.height &&
                rowStride == other.rowStride &&
                data.contentEquals(other.data)
            )

    override fun hashCode(): Int =
        (((data.contentHashCode() * 31 + width) * 31 + height) * 31) + rowStride
}

/**
 * Reads a QR code out of a camera frame, or returns `null` because there isn't one.
 *
 * ### Why [QRCodeReader] and not `MultiFormatReader`
 *
 * This is the direct analogue of iOS's `metadataObjectTypes = [.qr]`
 * (`ScannerViewController.swift:95`). `MultiFormatReader` would also find EAN-13 on
 * a cereal box and Code 128 on a parcel, neither of which can be a bitcoin
 * destination — so every one of those is a misread the user has to notice and undo.
 * A reader that can only produce QR cannot produce those at all, and it is several
 * times cheaper per frame, which matters when the frame rate is the scan rate.
 *
 * ### Not finding a code is the normal case
 *
 * Most frames contain no QR: the user is still moving the phone. ZXing signals that
 * by throwing, and at 30 frames a second that is 30 exceptions a second of stack
 * capture for an event that is not exceptional. That is what [NotFoundException]'s
 * cached, stackless instance is for, and it is why this returns `null` rather than
 * letting the throw out — a caller that has to `try`/`catch` its way through the
 * happy path will eventually catch something it should not have.
 */
internal class QrDecoder {

    private val reader = QRCodeReader()

    /**
     * `TRY_HARDER` spends more time per frame in exchange for reading codes that are
     * blurred, angled or partly shadowed — which is every real scan, because the
     * user is holding a phone at a screen or a printed slip. The cost is bounded by
     * the frame rate: a slower decode drops frames, it does not queue them, because
     * the analyser keeps only the latest.
     */
    private val hints = mapOf<DecodeHintType, Any>(DecodeHintType.TRY_HARDER to true)

    fun decode(frame: LuminanceFrame): String? {
        if (!frame.isReadable()) return null

        val source = try {
            PlanarYUVLuminanceSource(
                frame.data,
                // Row stride is the buffer's width, not the image's. Cropping back
                // to the image width is what removes the hardware's row padding.
                frame.rowStride,
                frame.height,
                0,
                0,
                frame.width,
                frame.height,
                false,
            )
        } catch (_: IllegalArgumentException) {
            // Geometry ZXing rejects outright. Belt and braces alongside
            // [isReadable]; either way a frame we cannot describe is a frame we
            // cannot read, and the next one will be along in 33 milliseconds.
            return null
        }

        return try {
            reader.decode(BinaryBitmap(HybridBinarizer(source)), hints).text
        } catch (_: NotFoundException) {
            // No QR in this frame. The overwhelmingly common outcome.
            null
        } catch (_: ChecksumException) {
            // A QR was found and its error correction could not save it — a blurred
            // or half-occluded code. Keep scanning rather than reporting a misread.
            null
        } catch (_: FormatException) {
            // Something QR-shaped that is not a QR code.
            null
        } finally {
            reader.reset()
        }
    }

    /**
     * Whether [data] actually holds the image its dimensions describe.
     *
     * ZXing does not check this. `PlanarYUVLuminanceSource` validates the crop
     * against the declared buffer geometry and then trusts the array, so a buffer
     * shorter than `(height - 1) * rowStride + width` passes construction and throws
     * [ArrayIndexOutOfBoundsException] from inside the binarizer instead — on the
     * analysis thread, where there is no user action to blame it on and the crash
     * report points at ZXing rather than at the frame that was wrong.
     *
     * A short frame is not a theoretical case: it is what a partial buffer read
     * produces, and [QrAnalyzer] copies only as much as the camera actually handed
     * over. Dropping the frame is right — it is one frame out of thirty a second.
     */
    private fun LuminanceFrame.isReadable(): Boolean {
        if (width <= 0 || height <= 0 || rowStride < width) return false
        return data.size >= (height - 1) * rowStride + width
    }
}
