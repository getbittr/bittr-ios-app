package com.bittr.android.feature.academy

import android.graphics.BitmapFactory
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Downloads a lesson's images.
 *
 * The iOS equivalent is `OneLessonViewController.getImage` plus `addImage`, and the
 * behaviour worth copying exactly is the failure path: `addImage` calls
 * `addNextComponent()` whether the download succeeded or not
 * (`Image.swift:69-79`), leaving an empty 30pt card in place of the picture. So a
 * dead URL costs a gap, never a stuck page — which is what lets `academy.yaml` gate
 * every tap on `academy.lessonSpinner` disappearing rather than on an image
 * appearing. [load] returns null instead of throwing for the same reason.
 *
 * No image library: this is two dozen lines against `HttpURLConnection` and
 * `BitmapFactory`, and the alternative is a dependency on the one screen in the app
 * that loads a remote image at all.
 */
internal interface LessonImageLoader {

    suspend fun load(url: String): ImageBitmap?
}

internal class HttpLessonImageLoader : LessonImageLoader {

    /**
     * Decoded images, by URL. Paging back to a page must not re-download it — iOS
     * gets that from `URLSession`'s shared cache; here the map is the cache.
     *
     * Bounded by the lesson content rather than by a policy: there are six image
     * components in the whole Academy.
     */
    private val cache = mutableMapOf<String, ImageBitmap?>()

    override suspend fun load(url: String): ImageBitmap? {
        cache[url]?.let { return it }

        val decoded = withContext(Dispatchers.IO) {
            runCatching {
                val connection = (URL(url).openConnection() as HttpURLConnection).apply {
                    connectTimeout = TIMEOUT_MS
                    readTimeout = TIMEOUT_MS
                }
                try {
                    if (connection.responseCode !in 200..299) return@runCatching null
                    val bytes = connection.inputStream.use { it.readBytes() }
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
                } finally {
                    connection.disconnect()
                }
            }.getOrNull()
        }

        if (decoded != null) cache[url] = decoded
        return decoded
    }

    private companion object {
        const val TIMEOUT_MS = 20_000
    }
}
