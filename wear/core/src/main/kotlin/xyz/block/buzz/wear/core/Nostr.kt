package xyz.block.buzz.wear.core

import fr.acinq.secp256k1.Secp256k1
import java.security.MessageDigest
import java.security.SecureRandom

/** A signed Nostr event (NIP-01). */
data class NostrEvent(
    val id: String,
    val pubkey: String,
    val createdAt: Long,
    val kind: Int,
    val tags: List<List<String>>,
    val content: String,
    val sig: String,
) {
    fun toJson(): String = buildString {
        append("{\"id\":").append(quote(id))
        append(",\"pubkey\":").append(quote(pubkey))
        append(",\"created_at\":").append(createdAt)
        append(",\"kind\":").append(kind)
        append(",\"tags\":").append(tagsJson(tags))
        append(",\"content\":").append(quote(content))
        append(",\"sig\":").append(quote(sig))
        append('}')
    }
}

/** The key the watch signs with: its owner's, handed over by their phone at pairing. */
class WatchKey private constructor(private val secret: ByteArray) {
    /** x-only public key, lowercase hex. */
    val pubkey: String = Secp256k1.pubkeyCreate(secret).copyOfRange(1, 33).toHex()

    fun secretHex(): String = secret.toHex()

    fun sign(kind: Int, tags: List<List<String>>, content: String, createdAt: Long = now()): NostrEvent {
        val serialized = "[0,${quote(pubkey)},$createdAt,$kind,${tagsJson(tags)},${quote(content)}]"
        val id = sha256(serialized.toByteArray(Charsets.UTF_8))
        val aux = ByteArray(32).also(random::nextBytes)
        val sig = Secp256k1.signSchnorr(id, secret, aux)
        return NostrEvent(id.toHex(), pubkey, createdAt, kind, tags, content, sig.toHex())
    }

    companion object {
        private val random = SecureRandom()

        fun generate(): WatchKey {
            while (true) {
                val candidate = ByteArray(32).also(random::nextBytes)
                if (Secp256k1.secKeyVerify(candidate)) return WatchKey(candidate)
            }
        }

        fun fromHex(hex: String): WatchKey {
            val bytes = hex.hexToBytes()
            require(bytes.size == 32 && Secp256k1.secKeyVerify(bytes)) { "invalid secret key" }
            return WatchKey(bytes)
        }
    }
}

fun verifyEvent(event: NostrEvent): Boolean {
    val serialized =
        "[0,${quote(event.pubkey)},${event.createdAt},${event.kind},${tagsJson(event.tags)},${quote(event.content)}]"
    val id = sha256(serialized.toByteArray(Charsets.UTF_8))
    if (id.toHex() != event.id) return false
    return runCatching {
        Secp256k1.verifySchnorr(event.sig.hexToBytes(), id, event.pubkey.hexToBytes())
    }.getOrDefault(false)
}

internal fun now(): Long = System.currentTimeMillis() / 1000

internal fun sha256(bytes: ByteArray): ByteArray = MessageDigest.getInstance("SHA-256").digest(bytes)

internal fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }

internal fun String.hexToBytes(): ByteArray {
    require(length % 2 == 0) { "odd hex length" }
    return ByteArray(length / 2) { substring(it * 2, it * 2 + 2).toInt(16).toByte() }
}

internal fun tagsJson(tags: List<List<String>>): String =
    tags.joinToString(",", "[", "]") { tag -> tag.joinToString(",", "[", "]", transform = ::quote) }

/** NIP-01 canonical string escaping: the event id depends on these exact bytes. */
internal fun quote(value: String): String = buildString(value.length + 2) {
    append('"')
    for (ch in value) {
        when (ch) {
            '"' -> append("\\\"")
            '\\' -> append("\\\\")
            '\n' -> append("\\n")
            '\r' -> append("\\r")
            '\t' -> append("\\t")
            '\b' -> append("\\b")
            '\u000c' -> append("\\f")
            else -> if (ch < ' ') append("\\u%04x".format(ch.code)) else append(ch)
        }
    }
    append('"')
}
