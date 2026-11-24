package xyz.block.buzz.wear.core

import java.net.URI
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MediaTest {
    private fun event(vararg tags: List<String>) = WatchKey.generate().sign(9, tags.toList(), "")

    @Test
    fun readsImagesAndVideosAndSkipsTheRest() {
        val found = attachments(
            event(
                listOf("imeta", "url https://r.example/media/a.png", "m image/png", "thumb https://r.example/media/a.t.jpg"),
                listOf("imeta", "url https://r.example/media/b.mp4", "m video/mp4", "image https://r.example/media/b.jpg", "duration 12.6"),
                listOf("imeta", "url https://r.example/media/v.mp4", "m video/mp4", "filename voice-note-1.mp4"),
                listOf("imeta", "url https://r.example/media/c.pdf", "m application/pdf"),
                listOf("imeta", "m image/png"),
            ),
        )
        assertEquals(
            listOf(
                Attachment("https://r.example/media/a.png", "https://r.example/media/a.t.jpg", false, null),
                Attachment("https://r.example/media/b.mp4", "https://r.example/media/b.jpg", true, 12),
            ),
            found,
        )
    }

    @Test
    fun signsOnlyRequestsToTheRelaysOwnMedia() {
        val fetcher = MediaFetcher("wss://r.example", WatchKey.generate())
        assertTrue(fetcher.isRelayMedia(URI("https://R.example/media/a.png")))
        assertFalse(fetcher.isRelayMedia(URI("https://r.example/other/a.png")))
        assertFalse(fetcher.isRelayMedia(URI("https://evil.example/media/a.png")))
        assertFalse(fetcher.isRelayMedia(URI("https://r.example:8443/media/a.png")))
        assertFalse(fetcher.isRelayMedia(URI("https://r.example.evil.example/media/a.png")))
    }
}
