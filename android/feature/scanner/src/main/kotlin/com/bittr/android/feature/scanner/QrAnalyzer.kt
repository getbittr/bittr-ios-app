package com.bittr.android.feature.scanner

import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The whole of what this app does with a camera frame.
 *
 * A frame arrives, its brightness plane is copied into a [LuminanceFrame], a QR
 * reader is pointed at it, and the frame is closed. Nothing is written to disk,
 * nothing is uploaded, and nothing survives the callback — which is what makes the
 * shipped sentence *"The camera is used only to read the code in front of it.
 * Nothing is recorded."* (DEV-37, BIT-15 -> `decision-brief` D1) a description of
 * the code rather than a promise about it.
 *
 * Closing the frame is not optional bookkeeping. CameraX lends the analyser one of a
 * small fixed pool of buffers; an unclosed one is never handed back, and after a
 * couple of them the camera silently stops delivering frames. The preview keeps
 * running, so the screen looks alive while the scanner has stopped scanning. Hence
 * the `use` block: there is no path out of [analyze] that does not release the
 * frame.
 *
 * ### One result, then silence
 *
 * iOS stops the capture session inside its first `metadataOutput` callback
 * (`ScannerViewController.swift:111-113`) so a code cannot be reported twice while
 * the dismiss animation runs. The same hazard exists here and is worse: frames are
 * already in flight on the analysis executor when the first result lands, and each
 * would route another destination into Send. [delivered] closes that window on the
 * analyser's own thread, before the UI has had a chance to react.
 */
internal class QrAnalyzer(
    private val decoder: QrDecoder = QrDecoder(),
    private val onCode: (String) -> Unit,
) : ImageAnalysis.Analyzer {

    private val delivered = AtomicBoolean(false)

    override fun analyze(image: ImageProxy) {
        image.use { frame ->
            if (delivered.get()) return
            val code = decoder.decode(frame.toLuminanceFrame()) ?: return
            if (delivered.compareAndSet(false, true)) onCode(code)
        }
    }
}

/**
 * Copies the frame's brightness plane out of the camera's buffer.
 *
 * Plane 0 of YUV_420_888 is luminance at full resolution; planes 1 and 2 are
 * chroma, subsampled, and of no use to a QR reader. The copy is deliberate — the
 * underlying buffer is reclaimed the moment the frame is closed, so a decoder
 * holding a reference to it would be reading whatever the camera wrote next.
 *
 * The array is sized by row stride rather than by width. ZXing is told the same
 * stride and asked to crop to the image, so padded rows cost a few kilobytes and
 * no correctness; sizing it by width instead would under-read every padded frame.
 */
private fun ImageProxy.toLuminanceFrame(): LuminanceFrame {
    val plane = planes[0]
    val buffer = plane.buffer.also { it.rewind() }
    val stride = plane.rowStride

    val data = ByteArray(stride * height)
    buffer.get(data, 0, minOf(buffer.remaining(), data.size))

    return LuminanceFrame(data = data, width = width, height = height, rowStride = stride)
}
