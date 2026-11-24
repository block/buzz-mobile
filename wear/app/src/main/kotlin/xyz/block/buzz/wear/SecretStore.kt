package xyz.block.buzz.wear

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.net.URI
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONArray
import org.json.JSONObject
import xyz.block.buzz.wear.core.WatchKey

/** One community the watch can sign in to: what to call it, where to connect and the key to sign with. */
internal data class Pairing(val name: String, val relayUrl: String, val secretHex: String) {
    companion object {
        /** A pairing from the phone's JSON, or null unless it names a secure relay and a usable key. */
        fun from(json: JSONObject): Pairing? = runCatching {
            val relay = json.getString("relay")
            val secret = json.getString("secret")
            require(relay.startsWith("wss://"))
            WatchKey.fromHex(secret)
            Pairing(json.optString("name").ifBlank { URI(relay).host ?: relay }, relay, secret)
        }.getOrNull()
    }
}

/**
 * Keeps the pairings on the watch. The signing keys are stored encrypted under
 * a key that lives in the Android Keystore and cannot be read out of it, so a
 * copy of the app's files is useless without this watch.
 */
internal object SecretStore {
    private const val PREFS = "paired"
    private const val ALIAS = "buzz-watch-pairing"

    /** Replace everything the watch holds with [pairings]; [active] is the relay to open first. */
    fun save(context: Context, pairings: List<Pairing>, active: String?) {
        val plain = JSONArray(
            pairings.map { JSONObject().put("name", it.name).put("relay", it.relayUrl).put("secret", it.secretHex) },
        ).toString()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, wrappingKey()) }
        val sealed = cipher.iv + cipher.doFinal(plain.toByteArray())
        prefs(context).edit()
            .remove("relay")
            .putString("active", pairings.firstOrNull { it.relayUrl == active }?.relayUrl ?: pairings.firstOrNull()?.relayUrl)
            .putString("key", Base64.encodeToString(sealed, Base64.NO_WRAP))
            .apply()
    }

    fun loadAll(context: Context): List<Pairing> {
        val sealed = prefs(context).getString("key", null)?.let { Base64.decode(it, Base64.NO_WRAP) } ?: return emptyList()
        return runCatching {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, wrappingKey(), GCMParameterSpec(128, sealed, 0, 12))
            val plain = String(cipher.doFinal(sealed, 12, sealed.size - 12))
            if (plain.startsWith("[")) {
                val list = JSONArray(plain)
                (0 until list.length()).mapNotNull { Pairing.from(list.getJSONObject(it)) }
            } else {
                // A watch paired before it could hold more than one community.
                val relay = prefs(context).getString("relay", null)
                listOfNotNull(Pairing.from(JSONObject().put("relay", relay).put("secret", plain)))
            }
        }.getOrDefault(emptyList())
    }

    /** The community to open: the one last chosen, else the first. */
    fun load(context: Context): Pairing? {
        val all = loadAll(context)
        val active = prefs(context).getString("active", null)
        return all.firstOrNull { it.relayUrl == active } ?: all.firstOrNull()
    }

    fun choose(context: Context, relayUrl: String) = prefs(context).edit().putString("active", relayUrl).apply()

    fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun wrappingKey(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(
                KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .build(),
            )
        }.generateKey()
    }
}
