package com.samsonlab.cinelark.remote

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLContext
import javax.net.ssl.X509TrustManager
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString

class LocalWebSocketBridge(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val connectivityManager =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val commands = MethodChannel(messenger, COMMAND_CHANNEL)
    private val events = EventChannel(messenger, EVENT_CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private var webSocket: WebSocket? = null
    private var client: OkHttpClient? = null
    private var pendingConnect: MethodChannel.Result? = null
    private var connectionGeneration = 0L

    fun register() {
        commands.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "connect" -> connect(call, result)
            "send" -> send(call, result)
            "close" -> close(result)
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        Log.i(TAG, "event_stream_listening")
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun connect(call: MethodCall, result: MethodChannel.Result) {
        Log.i(TAG, "connect_requested")
        val endpoint = call.argument<String>("endpoint")
        val fingerprint = call.argument<String>("fingerprint")
        if (endpoint == null || fingerprint == null) {
            result.error("invalidArguments", "Missing Remote endpoint or fingerprint.", null)
            return
        }
        val wifiNetwork = connectivityManager.allNetworks.firstOrNull { network ->
            val capabilities = connectivityManager.getNetworkCapabilities(network)
            capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true &&
                !capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
        }
        if (wifiNetwork == null) {
            Log.e(TAG, "connect_rejected reason=wifi_unavailable")
            result.error("wifiUnavailable", "No active Wi-Fi network is available.", null)
            return
        }

        val trustManager = try {
            FingerprintTrustManager(fingerprint)
        } catch (_: IllegalArgumentException) {
            result.error("invalidFingerprint", "The Remote fingerprint is invalid.", null)
            return
        }
        val sslContext = SSLContext.getInstance("TLS").apply {
            init(null, arrayOf(trustManager), SecureRandom())
        }
        connectionGeneration += 1
        val generation = connectionGeneration
        webSocket?.cancel()
        pendingConnect?.error("connectionReplaced", "Remote connection was replaced.", null)
        pendingConnect = result
        Log.i(TAG, "wifi_network_selected network=$wifiNetwork")
        client = OkHttpClient.Builder()
            .socketFactory(wifiNetwork.socketFactory)
            .sslSocketFactory(sslContext.socketFactory, trustManager)
            // The exact leaf certificate is verified above, including for numeric LAN hosts.
            .hostnameVerifier { _, _ -> true }
            .protocols(listOf(Protocol.HTTP_1_1))
            .connectTimeout(8, TimeUnit.SECONDS)
            .readTimeout(0, TimeUnit.MILLISECONDS)
            .build()
        val request = Request.Builder().url(endpoint).build()
        webSocket = client?.newWebSocket(request, Listener(generation))
    }

    private fun send(call: MethodCall, result: MethodChannel.Result) {
        val message = call.argument<String>("message")
        if (message == null) {
            result.error("invalidArguments", "Missing Remote message.", null)
            return
        }
        if (webSocket?.send(message) != true) {
            Log.e(TAG, "send_rejected reason=disconnected")
            result.error("disconnected", "Remote is disconnected.", null)
            return
        }
        Log.i(TAG, "message_sent chars=${message.length}")
        result.success(true)
    }

    private fun close(result: MethodChannel.Result) {
        Log.i(TAG, "close_requested")
        connectionGeneration += 1
        pendingConnect?.error("connectionClosed", "Remote connection was closed.", null)
        pendingConnect = null
        webSocket?.close(1000, "client_closed")
        webSocket = null
        client = null
        result.success(null)
    }

    private fun dispatch(action: () -> Unit) {
        mainHandler.post(action)
    }

    private inner class Listener(
        private val generation: Long,
    ) : WebSocketListener() {
        override fun onOpen(webSocket: WebSocket, response: Response) {
            dispatchIfCurrent("open") {
                Log.i(TAG, "websocket_opened")
                pendingConnect?.success(true)
                pendingConnect = null
            }
        }

        override fun onMessage(webSocket: WebSocket, text: String) {
            dispatchIfCurrent("message") {
                Log.i(TAG, "message_received chars=${text.length}")
                eventSink?.success(mapOf("type" to "message", "data" to text))
            }
        }

        override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
            dispatchIfCurrent("binary_message") {
                Log.e(TAG, "binary_message_rejected bytes=${bytes.size}")
                webSocket.close(1003, "binary_unsupported")
            }
        }

        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            dispatchIfCurrent("closed") {
                Log.i(TAG, "websocket_closed code=$code reason=$reason")
                this@LocalWebSocketBridge.webSocket = null
                eventSink?.success(
                    mapOf("type" to "closed", "code" to code, "reason" to reason),
                )
            }
        }

        override fun onFailure(webSocket: WebSocket, error: Throwable, response: Response?) {
            dispatchIfCurrent("failure") {
                Log.e(
                    TAG,
                    "websocket_failed type=${error.javaClass.simpleName} message=${error.message}",
                )
                this@LocalWebSocketBridge.webSocket = null
                val connect = pendingConnect
                pendingConnect = null
                if (connect != null) {
                    connect.error("connectionFailed", "Could not connect to the Mac.", null)
                } else {
                    eventSink?.error("connectionFailed", "Remote connection failed.", null)
                }
            }
        }

        private fun dispatchIfCurrent(event: String, action: () -> Unit) {
            dispatch {
                if (generation != connectionGeneration) {
                    Log.i(TAG, "stale_callback_ignored event=$event")
                    return@dispatch
                }
                action()
            }
        }
    }

    private class FingerprintTrustManager(encodedFingerprint: String) : X509TrustManager {
        private val expectedFingerprint = Base64.decode(
            encodedFingerprint,
            Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP,
        ).also { require(it.size == SHA256_BYTES) }

        override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) {
            throw CertificateException("Client certificates are not supported.")
        }

        override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {
            val certificate = chain.firstOrNull()
                ?: throw CertificateException("The server certificate is missing.")
            val actual = MessageDigest.getInstance("SHA-256").digest(certificate.encoded)
            if (!MessageDigest.isEqual(actual, expectedFingerprint)) {
                throw CertificateException("The server certificate fingerprint does not match.")
            }
            Log.i(TAG, "certificate_fingerprint_verified")
        }

        override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
    }

    private companion object {
        const val COMMAND_CHANNEL = "com.samsonlab.cinelark.remote/websocket"
        const val EVENT_CHANNEL = "com.samsonlab.cinelark.remote/websocket-events"
        const val SHA256_BYTES = 32
        const val TAG = "CineLarkRemote"
    }
}
