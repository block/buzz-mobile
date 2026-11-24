package xyz.block.buzz.wear.core

import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.TimeUnit

/**
 * One authenticated connection from the watch to a relay: NIP-42 login with
 * the key the watch holds, then publish, query and subscribe.
 */
class RelayConnection(
    private val relayUrl: String,
    private val key: WatchKey,
    private val client: OkHttpClient = OkHttpClient.Builder().pingInterval(25, TimeUnit.SECONDS).build(),
    /** Called once if the connection drops after a successful login. */
    private val onLost: (String) -> Unit = {},
) : AutoCloseable {
    private val authenticated = CompletableFuture<Unit>()
    private val pendingOk = ConcurrentHashMap<String, CompletableFuture<String>>()
    private val subscriptions = ConcurrentHashMap<String, (NostrEvent) -> Unit>()
    private val ends = ConcurrentHashMap<String, CompletableFuture<Unit>>()
    private val counter = AtomicInteger()
    private val lost = java.util.concurrent.atomic.AtomicBoolean()
    private var authEventId: String? = null
    private var socket: WebSocket? = null

    /** Connect and complete the relay login, or throw with the relay's reason. */
    fun connect(timeoutSeconds: Long = 15) {
        val request = Request.Builder().url(relayUrl).build()
        socket = client.newWebSocket(request, Listener())
        authenticated.get(timeoutSeconds, TimeUnit.SECONDS)
    }

    /** Publish a channel message (kind 9, NIP-29 `h` tag). Returns the event id. */
    fun sendMessage(channelId: String, text: String, extraTags: List<List<String>> = emptyList()): String {
        val event = key.sign(9, listOf(listOf("h", channelId)) + extraTags, text)
        publish(event)
        return event.id
    }

    fun publish(event: NostrEvent, timeoutSeconds: Long = 15) {
        val ok = CompletableFuture<String>()
        pendingOk[event.id] = ok
        send("[\"EVENT\",${event.toJson()}]")
        ok.get(timeoutSeconds, TimeUnit.SECONDS)
    }

    /** Live channel messages and activity signals from now on. Returns an id for [unsubscribe]. */
    fun subscribe(channelId: String, onEvent: (NostrEvent) -> Unit): String {
        val id = "watch-${counter.incrementAndGet()}"
        subscriptions[id] = onEvent
        val filter = JSONObject()
            // 20002 is the short-lived "working on it" signal agents send.
            .put("kinds", JSONArray(listOf(9, 20002)))
            .put("#h", JSONArray(listOf(channelId)))
            .put("since", now())
        send("[\"REQ\",${quote(id)},$filter]")
        return id
    }

    fun unsubscribe(id: String) {
        subscriptions.remove(id)
        runCatching { send("[\"CLOSE\",${quote(id)}]") }
    }

    /** What the relay holds for [filter] right now. Empty if it does not answer in time. */
    fun query(filter: JSONObject, timeoutSeconds: Long = 10): List<NostrEvent> {
        val id = "query-${counter.incrementAndGet()}"
        val found = CopyOnWriteArrayList<NostrEvent>()
        val done = CompletableFuture<Unit>()
        subscriptions[id] = { found.add(it) }
        ends[id] = done
        send("[\"REQ\",${quote(id)},$filter]")
        runCatching { done.get(timeoutSeconds, TimeUnit.SECONDS) }
        ends.remove(id)
        unsubscribe(id)
        return found
    }

    override fun close() {
        lost.set(true)
        socket?.close(1000, null)
        client.dispatcher.executorService.shutdown()
    }

    private fun send(frame: String) {
        val open = socket ?: error("not connected")
        check(open.send(frame)) { "relay connection is closed" }
    }

    private inner class Listener : WebSocketListener() {
        override fun onMessage(webSocket: WebSocket, text: String) {
            val frame = runCatching { JSONArray(text) }.getOrNull() ?: return
            when (frame.optString(0)) {
                "AUTH" -> {
                    val event = key.sign(
                        22242,
                        listOf(listOf("relay", relayUrl), listOf("challenge", frame.optString(1))),
                        "",
                    )
                    authEventId = event.id
                    webSocket.send("[\"AUTH\",${event.toJson()}]")
                }
                "OK" -> {
                    val id = frame.optString(1)
                    val accepted = frame.optBoolean(2)
                    val message = frame.optString(3)
                    if (id == authEventId) {
                        if (accepted) authenticated.complete(Unit)
                        else authenticated.completeExceptionally(RelayRefused("login refused: $message"))
                    } else {
                        pendingOk.remove(id)?.let {
                            if (accepted) it.complete(message)
                            else it.completeExceptionally(RelayRefused("event refused: $message"))
                        }
                    }
                }
                "EVENT" -> {
                    val event = parseEvent(frame.optJSONObject(2) ?: return) ?: return
                    if (verifyEvent(event)) subscriptions[frame.optString(1)]?.invoke(event)
                }
                "EOSE" -> ends.remove(frame.optString(1))?.complete(Unit)
                "CLOSED" -> {
                    subscriptions.remove(frame.optString(1))
                    ends.remove(frame.optString(1))?.complete(Unit)
                }
            }
        }

        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
            val reason = response?.let { "HTTP ${it.code}" } ?: t.toString()
            fail(RelayRefused("connection failed: $reason"))
        }

        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            fail(RelayRefused("connection closed: $code $reason"))
        }

        private fun fail(error: Throwable) {
            val wasConnected = authenticated.isDone && !authenticated.isCompletedExceptionally
            if (wasConnected && lost.compareAndSet(false, true)) onLost(error.message ?: "connection lost")
            authenticated.completeExceptionally(error)
            pendingOk.values.forEach { it.completeExceptionally(error) }
            pendingOk.clear()
        }
    }
}

class RelayRefused(message: String) : Exception(message)

internal fun parseEvent(json: JSONObject): NostrEvent? = runCatching {
    val tags = json.getJSONArray("tags")
    NostrEvent(
        id = json.getString("id"),
        pubkey = json.getString("pubkey"),
        createdAt = json.getLong("created_at"),
        kind = json.getInt("kind"),
        tags = List(tags.length()) { i ->
            val tag = tags.getJSONArray(i)
            List(tag.length()) { j -> tag.getString(j) }
        },
        content = json.getString("content"),
        sig = json.getString("sig"),
    )
}.getOrNull()
