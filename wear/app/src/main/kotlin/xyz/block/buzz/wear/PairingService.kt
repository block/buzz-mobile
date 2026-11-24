package xyz.block.buzz.wear

import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import org.json.JSONObject

/**
 * Receives the pairing from the owner's phone over the Wear Data Layer. The
 * system delivers these messages only from the same app, signed with the same
 * certificate, on a phone paired with this watch.
 */
class PairingService : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        if (event.path != PAIR_PATH) return
        val json = runCatching { JSONObject(String(event.data)) }.getOrNull() ?: return
        // One entry per community the owner chose on the phone.
        val list = json.optJSONArray("communities")
        val pairings = if (list == null) {
            listOfNotNull(Pairing.from(json))
        } else {
            (0 until list.length()).mapNotNull { index -> list.optJSONObject(index)?.let(Pairing::from) }
        }.distinctBy { it.relayUrl }
        if (pairings.isEmpty()) return
        SecretStore.save(this, pairings, json.optString("active"))
    }
}

internal const val PAIR_PATH = "/buzz/pair"
