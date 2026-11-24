package xyz.block.buzz.mobile

import android.content.Context
import com.google.android.gms.wearable.Wearable
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Hands a pairing to this phone's watches over the Wear Data Layer. The
 * system delivers it only to the same app, signed with the same certificate,
 * on a watch paired with this phone.
 */
internal class WatchPairingPlugin(context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "buzz/watch_pairing")
    private val app = context.applicationContext

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                // Names of the watches in reach, for the owner to confirm.
                "watches" -> Wearable.getNodeClient(app).connectedNodes
                    .addOnSuccessListener { nodes -> result.success(nodes.map { it.displayName }) }
                    .addOnFailureListener { result.error("unavailable", it.message, null) }
                "pair" -> {
                    val payload = call.arguments as? ByteArray
                    if (payload == null) {
                        result.error("invalid_arguments", "Expected the pairing bytes.", null)
                        return@setMethodCallHandler
                    }
                    Wearable.getNodeClient(app).connectedNodes
                        .addOnSuccessListener { nodes ->
                            if (nodes.isEmpty()) {
                                result.error("no_watch", "No watch is connected.", null)
                                return@addOnSuccessListener
                            }
                            var pending = nodes.size
                            var sent = 0
                            for (node in nodes) {
                                Wearable.getMessageClient(app).sendMessage(node.id, PAIR_PATH, payload)
                                    .addOnSuccessListener { sent++ }
                                    .addOnCompleteListener {
                                        if (--pending == 0) {
                                            if (sent > 0) result.success(sent)
                                            else result.error("not_sent", "The watch did not take the pairing.", null)
                                        }
                                    }
                            }
                        }
                        .addOnFailureListener { result.error("unavailable", it.message, null) }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() { channel.setMethodCallHandler(null) }

    private companion object {
        const val PAIR_PATH = "/buzz/pair"
    }
}
