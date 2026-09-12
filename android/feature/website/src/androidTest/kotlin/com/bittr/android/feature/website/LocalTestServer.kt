package com.bittr.android.feature.website

import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.InetAddress
import java.net.ServerSocket
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.concurrent.thread

/**
 * A four-route HTTP server on loopback, for the isolation tests.
 *
 * Hand-written rather than MockWebServer to keep a test-only OkHttp dependency
 * out of the module. It needs to do three things and does exactly those: serve a
 * page, record which paths were requested, and be on an origin that is not on
 * [FirstPartyOrigins]'s allowlist.
 *
 * The recording is the point. "No network call was made" is only checkable
 * against something that would have noticed one, so [requestedPaths] is the
 * assertion surface: the LNURL endpoint routes exist and must never be hit.
 */
internal class LocalTestServer {

    private val socket = ServerSocket(0, 1, InetAddress.getByName("127.0.0.1"))
    private val recorded = CopyOnWriteArrayList<String>()

    /** Origin of this server. Not on the allowlist, so pages it serves are third-party. */
    val origin: String = "http://127.0.0.1:${socket.localPort}"

    /** Every path requested, in order. Thread-safe: requests land on the accept thread. */
    val requestedPaths: List<String> get() = recorded.toList()

    fun start(pages: Map<String, String>) {
        thread(isDaemon = true, name = "LocalTestServer") {
            while (!socket.isClosed) {
                val client = try {
                    socket.accept()
                } catch (_: Exception) {
                    return@thread
                }
                client.use { connection ->
                    val reader = BufferedReader(InputStreamReader(connection.getInputStream()))
                    val requestLine = reader.readLine() ?: return@use
                    val path = requestLine.split(' ').getOrNull(1) ?: "/"
                    recorded.add(path)

                    val body = pages[path.substringBefore('?')]
                    val response = if (body == null) {
                        "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                    } else {
                        val bytes = body.toByteArray()
                        "HTTP/1.1 200 OK\r\n" +
                            "Content-Type: text/html; charset=utf-8\r\n" +
                            "Content-Length: ${bytes.size}\r\n" +
                            "Connection: close\r\n\r\n" +
                            body
                    }
                    connection.getOutputStream().apply {
                        write(response.toByteArray())
                        flush()
                    }
                }
            }
        }
    }

    fun stop() {
        socket.close()
    }
}
