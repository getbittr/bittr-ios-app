package com.bittr.android.feature.scanner

import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.common.BitMatrix
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The Definition of Done's *"decodes a QR to a destination string"*, on the JVM.
 *
 * There is no Android in this test and no emulator behind it: [QrDecoder] takes a
 * plain brightness buffer, which is the whole reason it takes one. A QR is encoded
 * here, laid out as the bytes a camera would hand over, and read back. If it comes
 * back wrong, the scanner is wrong — not the camera, not the device, not the
 * lighting.
 *
 * The destinations below are real formats, not `"hello"`: a P2WPKH address, a
 * BIP-21 URI with an amount, a BOLT-11 invoice and an LNURL. They are the four
 * shapes `handleScannedOrPastedString` branches on (`AddressParsing.swift:15-60`),
 * and three of them are long enough to push the QR to a version where the decoder
 * has real work to do. A 20-character test string would pass on a decoder that
 * could not read anything a user will actually scan.
 */
class QrDecoderTest {

    private val decoder = QrDecoder()

    private companion object {
        const val ADDRESS = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
        const val BIP21 = "bitcoin:bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq?amount=0.00125"
        const val INVOICE =
            "lnbc2500u1pvjluezsp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygspp5" +
                "qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdq5xysxxatsyp3k7enxv4js" +
                "n2vpsxgerhwfjhg"
        const val LNURL =
            "LNURL1DP68GURN8GHJ7UM9WFMXJCM99E3K7MF0V9CXJ0M385EKVCENXC6R2C35XVUKXEFCV5MKVV34X"
    }

    @Test
    fun `reads an on-chain address off a frame`() {
        assertEquals(ADDRESS, decoder.decode(frameOf(ADDRESS)))
    }

    @Test
    fun `reads a BIP-21 URI carrying an amount`() {
        assertEquals(BIP21, decoder.decode(frameOf(BIP21)))
    }

    @Test
    fun `reads a lightning invoice`() {
        assertEquals(INVOICE, decoder.decode(frameOf(INVOICE)))
    }

    @Test
    fun `reads an LNURL`() {
        assertEquals(LNURL, decoder.decode(frameOf(LNURL)))
    }

    /**
     * The decoder is reusable, because the analyser calls it on every frame.
     *
     * ZXing readers carry per-decode state and need resetting between calls. A
     * decoder that works once and then reads the first code forever is a scanner
     * that puts the previous user's address in the field.
     */
    @Test
    fun `reads different codes from consecutive frames`() {
        assertEquals(ADDRESS, decoder.decode(frameOf(ADDRESS)))
        assertEquals(INVOICE, decoder.decode(frameOf(INVOICE)))
        assertEquals(ADDRESS, decoder.decode(frameOf(ADDRESS)))
    }

    /**
     * Rotation does not matter, and this is why the analyser does not correct for it.
     *
     * ZXing finds a QR by scanning horizontal rows for the 1:1:3:1:1 ratio of a
     * finder pattern, and a finder pattern is square — a code turned on its side
     * still presents that ratio to a horizontal scan. Rotating the buffer to match
     * the device orientation would cost a full copy per frame for nothing.
     */
    @Test
    fun `reads a code that is not upright`() {
        assertEquals(ADDRESS, decoder.decode(frameOf(ADDRESS).rotatedQuarterTurn()))
    }

    /** Most frames are this one. */
    @Test
    fun `returns null for a frame with no code in it`() {
        val blank = LuminanceFrame(ByteArray(400 * 400) { -1 }, width = 400, height = 400)
        assertNull(decoder.decode(blank))
    }

    /**
     * Row padding is handled, and getting it wrong is silent.
     *
     * Camera hardware pads each row of the brightness plane out to an alignment it
     * likes, so the buffer is wider than the image. A decoder that assumes the two
     * are equal reads a diagonally sheared image and simply finds nothing — no
     * crash, no error, just a scanner that never scans, on the subset of devices
     * whose preferred stride is not the resolution.
     */
    @Test
    fun `reads a frame whose rows are padded`() {
        assertEquals(ADDRESS, decoder.decode(frameOf(ADDRESS, extraStride = 37)))
    }

    /**
     * A frame that does not describe itself is dropped, not thrown.
     *
     * ZXing validates the crop against the declared geometry and then trusts the
     * array, so a short buffer gets through construction and throws from inside the
     * binarizer — on the analysis thread, where the crash report names ZXing rather
     * than the frame that was wrong. Each of these is one frame out of thirty a
     * second; none of them is worth taking the app down for.
     */
    @Test
    fun `returns null rather than throwing on a frame it cannot read`() {
        assertNull(decoder.decode(LuminanceFrame(ByteArray(16), width = 400, height = 400)))
        assertNull(decoder.decode(LuminanceFrame(ByteArray(0), width = 0, height = 0)))
        assertNull(
            // Stride narrower than the image: not a frame, whatever it is.
            decoder.decode(LuminanceFrame(ByteArray(400 * 400), 400, 400, rowStride = 8)),
        )
    }

    /**
     * Encodes [text] as a QR and lays it out the way the camera hands one over:
     * one byte of brightness per pixel, `0` for a dark module and `-1` (0xFF) for a
     * light one, rows [extraStride] bytes further apart than the image is wide.
     */
    private fun frameOf(text: String, extraStride: Int = 0): LuminanceFrame {
        val matrix: BitMatrix = QRCodeWriter().encode(
            text,
            BarcodeFormat.QR_CODE,
            400,
            400,
            mapOf(
                EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M,
                // A quiet zone is part of the spec — a QR with no margin is one a
                // reader is entitled to miss, so testing without it would be
                // testing a code no printer would produce.
                EncodeHintType.MARGIN to 16,
            ),
        )

        val width = matrix.width
        val height = matrix.height
        val stride = width + extraStride
        val data = ByteArray(stride * height) { -1 }

        for (y in 0 until height) {
            for (x in 0 until width) {
                if (matrix[x, y]) data[y * stride + x] = 0
            }
        }

        return LuminanceFrame(data = data, width = width, height = height, rowStride = stride)
    }

    /** The same frame, turned 90°, with the padding dropped. */
    private fun LuminanceFrame.rotatedQuarterTurn(): LuminanceFrame {
        val rotated = ByteArray(width * height)
        for (y in 0 until height) {
            for (x in 0 until width) {
                rotated[x * height + (height - 1 - y)] = data[y * rowStride + x]
            }
        }
        return LuminanceFrame(
            data = rotated,
            width = height,
            height = width,
            rowStride = height,
        )
    }
}
