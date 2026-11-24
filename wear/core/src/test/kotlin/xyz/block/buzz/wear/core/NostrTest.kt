package xyz.block.buzz.wear.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class NostrTest {
    @Test
    fun derivesTheBip340PublicKey() {
        // BIP-340 test vector 0: secret key 3.
        val key = WatchKey.fromHex("0000000000000000000000000000000000000000000000000000000000000003")
        assertEquals("f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9", key.pubkey)
    }

    @Test
    fun signsEventsThatVerifyAndRejectsTampering() {
        val key = WatchKey.generate()
        val event = key.sign(9, listOf(listOf("h", "channel")), "line one\n\"quoted\" \\ tab\t é 🐝")
        assertTrue(verifyEvent(event))
        assertFalse(verifyEvent(event.copy(content = event.content + "!")))
        assertFalse(verifyEvent(event.copy(pubkey = WatchKey.generate().pubkey)))
    }

    @Test
    fun computesTheCanonicalEventId() {
        val key = WatchKey.fromHex("0000000000000000000000000000000000000000000000000000000000000003")
        val event = key.sign(1, listOf(listOf("t", "a\"b")), "hi\n", createdAt = 1700000000)
        val expected = sha256(
            ("[0,\"${key.pubkey}\",1700000000,1,[[\"t\",\"a\\\"b\"]],\"hi\\n\"]").toByteArray(),
        ).toHex()
        assertEquals(expected, event.id)
    }
}
