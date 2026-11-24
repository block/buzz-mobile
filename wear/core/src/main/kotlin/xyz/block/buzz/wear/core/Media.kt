package xyz.block.buzz.wear.core

import okhttp3.OkHttpClient
import okhttp3.Request
import java.net.URI
import java.util.Base64
import java.util.concurrent.TimeUnit

/** An attachment on a message, from its NIP-92 `imeta` tag. */
data class Attachment(
    val url: String,
    /** A small still to show in the conversation: the thumbnail, or a video's preview frame. */
    val preview: String?,
    val video: Boolean,
    val durationSeconds: Int?,
)

/** The images and videos attached to [event]. Other file types are left to the message text. */
fun attachments(event: NostrEvent): List<Attachment> = event.tags.mapNotNull { tag ->
    if (tag.firstOrNull() != "imeta") return@mapNotNull null
    val fields = tag.drop(1).mapNotNull { part ->
        val space = part.indexOf(' ')
        if (space <= 0) null else part.substring(0, space) to part.substring(space + 1)
    }.toMap()
    val url = fields["url"]?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
    val type = fields["m"].orEmpty()
    // Voice notes travel as small MP4 files; they are not something to look at.
    if (fields["filename"].orEmpty().startsWith("voice-note-")) return@mapNotNull null
    when {
        type.startsWith("image/") -> Attachment(url, fields["thumb"] ?: url, video = false, durationSeconds = null)
        type.startsWith("video/") -> Attachment(
            url,
            fields["image"] ?: fields["thumb"],
            video = true,
            durationSeconds = fields["duration"]?.toDoubleOrNull()?.takeIf { it.isFinite() && it >= 0 }?.toInt(),
        )
        else -> null
    }
}

/**
 * Downloads media. The relay's own media is private, so those requests carry
 * a short-lived proof signed by the owner's key (Blossom BUD-01). The proof is
 * sent only to the relay itself, never to another host.
 */
class MediaFetcher(
    relayUrl: String,
    private val key: WatchKey,
    private val client: OkHttpClient = OkHttpClient.Builder().callTimeout(30, TimeUnit.SECONDS).build(),
) {
    private val relay = URI(relayUrl)

    /** The bytes at [url], or null if it cannot be fetched or is larger than [maxBytes]. */
    fun fetch(url: String, maxBytes: Long = 12L * 1024 * 1024): ByteArray? = runCatching {
        val target = URI(url)
        if (target.scheme != "https") return null
        val request = Request.Builder().url(url).apply {
            if (isRelayMedia(target)) header("Authorization", "Nostr ${proof()}")
        }.build()
        client.newCall(request).execute().use { response ->
            val body = response.body ?: return null
            if (!response.isSuccessful || body.contentLength() > maxBytes) return null
            val source = body.source()
            // A missing length header must not let a huge download through.
            if (source.request(maxBytes + 1)) return null
            source.buffer.readByteArray()
        }
    }.getOrNull()

    internal fun isRelayMedia(target: URI): Boolean =
        target.host != null && target.host.equals(relay.host, ignoreCase = true) &&
            effectivePort(target) == effectivePort(relay) && target.path.orEmpty().startsWith("/media/")

    private fun effectivePort(uri: URI) = if (uri.port == -1) 443 else uri.port

    private fun proof(): String {
        val authority = relay.host.lowercase() + if (relay.port == -1) "" else ":${relay.port}"
        val event = key.sign(
            24242,
            listOf(listOf("t", "get"), listOf("expiration", (now() + 60).toString()), listOf("server", authority)),
            "Get buzz-media",
        )
        return Base64.getUrlEncoder().withoutPadding().encodeToString(event.toJson().toByteArray(Charsets.UTF_8))
    }
}
