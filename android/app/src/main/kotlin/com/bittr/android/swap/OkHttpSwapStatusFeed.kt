package com.bittr.android.swap

import com.bittr.android.core.swaps.BoltzApi
import com.bittr.android.core.swaps.SwapStatusFeed
import com.bittr.android.core.swaps.SwapStatusUpdate
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.isActive
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener

/**
 * Boltz's websocket — `WebSocketManager`: subscribe to `swap.update` for one swap on open, read
 * `args[0].status`, and reconnect three seconds after a close for as long as someone is collecting.
 *
 * iOS also drops the socket when the app is backgrounded; here collection stops with the
 * coordinator's interest instead, and a push or the refresh button covers the time in between.
 */
class OkHttpSwapStatusFeed(
    private val url: String,
    private val client: OkHttpClient = OkHttpClient(),
) : SwapStatusFeed {

    override fun updates(swapId: String): Flow<SwapStatusUpdate> = flow {
        while (currentCoroutineContext().isActive) {
            emitAll(session(swapId))
            delay(RECONNECT_MS)
        }
    }

    private fun session(swapId: String): Flow<SwapStatusUpdate> = callbackFlow {
        val socket = client.newWebSocket(
            Request.Builder().url(url).build(),
            object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    webSocket.send(BoltzApi.subscribeMessage(swapId))
                }

                override fun onMessage(webSocket: WebSocket, text: String) {
                    BoltzApi.parseSocketMessage(text)?.let { trySend(it) }
                }

                override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                    webSocket.close(NORMAL_CLOSURE, null)
                    channel.close()
                }

                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                    channel.close()
                }
            },
        )
        awaitClose { socket.cancel() }
    }

    private companion object {
        const val RECONNECT_MS = 3_000L
        const val NORMAL_CLOSURE = 1000
    }
}
