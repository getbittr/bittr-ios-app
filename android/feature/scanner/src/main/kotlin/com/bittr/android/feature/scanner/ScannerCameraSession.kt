package com.bittr.android.feature.scanner

import androidx.camera.compose.CameraXViewfinder
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.SurfaceRequest
import androidx.camera.core.Preview as CameraPreview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import java.util.concurrent.Executors

/**
 * The camera, bound.
 *
 * **This function is the "nothing is recorded" claim.** Two use cases go to
 * [ProcessCameraProvider.bindToLifecycle] below — a viewfinder and an analyser —
 * and CameraX offers exactly two more that would change the answer: one for stills
 * and one for video. Neither is on this module's dependency graph, neither is named
 * anywhere in this repo outside the test that bans them, and adding either would be
 * a one-line change here that scans just as well, passes every flow, and quietly
 * makes a sentence bittr has shipped to users false. `CameraCaptureGuardTest` in
 * `:app` is what notices.
 *
 * The analyser is the whole of the data path: a frame arrives, [QrAnalyzer] reads
 * its brightness plane, and the frame is closed. The viewfinder draws frames and
 * keeps none. Nothing is written to disk and nothing is uploaded.
 *
 * This mirrors iOS, where the same screen attaches an `AVCaptureVideoPreviewLayer`
 * and an `AVCaptureMetadataOutput` limited to `[.qr]`, and no photo or movie output
 * (`ScannerViewController.swift:89-103`).
 */
@Composable
internal fun ScannerViewfinder(
    onCode: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    var surfaceRequest by remember { mutableStateOf<SurfaceRequest?>(null) }

    // Analysis off the main thread. On it, a slow decode stalls the frame the
    // viewfinder is trying to draw, and the preview stutters in time with the
    // scanning — which reads as a broken camera rather than a busy one.
    val analysisExecutor = remember { Executors.newSingleThreadExecutor() }

    // The callback can change between recompositions; the binding below must not be
    // torn down and rebuilt when it does — rebinding restarts the camera, which is
    // a visible black flash.
    val currentOnCode by rememberUpdatedState(onCode)

    DisposableEffect(lifecycleOwner) {
        val mainExecutor = ContextCompat.getMainExecutor(context)
        val providerFuture = ProcessCameraProvider.getInstance(context)
        var boundProvider: ProcessCameraProvider? = null

        providerFuture.addListener(
            {
                val provider = runCatching { providerFuture.get() }.getOrNull() ?: return@addListener
                boundProvider = provider

                val viewfinder = CameraPreview.Builder().build().apply {
                    // Single-argument overload: CameraX delivers the request on the
                    // main thread, which is where this Compose state must be written.
                    setSurfaceProvider { request -> surfaceRequest = request }
                }

                val analysis = ImageAnalysis.Builder()
                    // Drop frames rather than queue them. The alternative
                    // back-pressure strategy blocks the camera until the analyser
                    // catches up, so a decode slower than the frame rate turns into
                    // ever-growing latency between what is in front of the lens and
                    // what is on screen.
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                    .apply {
                        setAnalyzer(
                            analysisExecutor,
                            QrAnalyzer { code ->
                                // Hop to the main thread: the caller navigates, and
                                // this arrives on the analysis executor.
                                mainExecutor.execute { currentOnCode(code) }
                            },
                        )
                    }

                // Anything this process had bound is gone; the scanner owns the
                // camera while it is on screen.
                provider.unbindAll()
                runCatching {
                    provider.bindToLifecycle(
                        lifecycleOwner,
                        CameraSelector.DEFAULT_BACK_CAMERA,
                        viewfinder,
                        analysis,
                    )
                }
            },
            mainExecutor,
        )

        onDispose {
            boundProvider?.unbindAll()
            analysisExecutor.shutdown()
        }
    }

    Box(modifier = modifier) {
        surfaceRequest?.let { request ->
            CameraXViewfinder(
                surfaceRequest = request,
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}
