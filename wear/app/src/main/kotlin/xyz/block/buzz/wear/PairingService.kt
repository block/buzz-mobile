package xyz.block.buzz.wear

import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import org.json.JSONObject
import xyz.block.buzz.wear.core.WatchKey

/**
 * Receives the pairing from the owner's phone over the Wear Data Layer. The
 * system delivers these messages only from the same app, signed with the same
 * certificate, on a phone paired with this watch.
 */
class PairingService : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        if (event.path != PAIR_PATH) return
        val pairing = runCatching {
            val json = JSONObject(String(event.data))
            val relay = json.getString("relay")
            val secret = json.getString("secret")
            require(relay.startsWith("wss://"))
            WatchKey.fromHex(secret)
            Pairing(relay, secret)
        }.getOrNull() ?: return
        SecretStore.save(this, pairing)
    }
}

internal const val PAIR_PATH = "/buzz/pair"
