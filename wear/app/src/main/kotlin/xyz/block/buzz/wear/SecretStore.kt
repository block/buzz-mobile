package xyz.block.buzz.wear

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** What pairing leaves on the watch: where to connect and the key to sign with. */
internal data class Pairing(val relayUrl: String, val secretHex: String)

/**
 * Keeps the pairing on the watch. The signing key is stored encrypted under a
 * key that lives in the Android Keystore and cannot be read out of it, so a
 * copy of the app's files is useless without this watch.
 */
internal object SecretStore {
    private const val PREFS = "paired"
    private const val ALIAS = "buzz-watch-pairing"

    fun save(context: Context, pairing: Pairing) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, wrappingKey()) }
        val sealed = cipher.iv + cipher.doFinal(pairing.secretHex.toByteArray())
        prefs(context).edit()
            .putString("relay", pairing.relayUrl)
            .putString("key", Base64.encodeToString(sealed, Base64.NO_WRAP))
            .apply()
    }

    fun load(context: Context): Pairing? {
        val relay = prefs(context).getString("relay", null) ?: return null
        val sealed = prefs(context).getString("key", null)?.let { Base64.decode(it, Base64.NO_WRAP) } ?: return null
        return runCatching {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, wrappingKey(), GCMParameterSpec(128, sealed, 0, 12))
            Pairing(relay, String(cipher.doFinal(sealed, 12, sealed.size - 12)))
        }.getOrNull()
    }

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
