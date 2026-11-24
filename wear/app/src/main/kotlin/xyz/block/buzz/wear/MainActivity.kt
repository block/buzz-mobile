package xyz.block.buzz.wear

import android.Manifest
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.json.JSONArray
import org.json.JSONObject
import xyz.block.buzz.wear.core.Attachment
import xyz.block.buzz.wear.core.MediaFetcher
import xyz.block.buzz.wear.core.NostrEvent
import xyz.block.buzz.wear.core.attachments
import xyz.block.buzz.wear.core.RelayConnection
import xyz.block.buzz.wear.core.WatchKey
import java.util.concurrent.Executors

internal data class Line(val mine: Boolean, val text: String, val media: List<Attachment> = emptyList())

/** Something to pick from a list: a channel or an agent. */
internal data class Choice(val id: String, val name: String, val picture: String? = null)

private enum class Screen { Chat, Channels, Agents, Compose, Listen, Type, Emoji, Image }

class MainActivity : ComponentActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private var status by mutableStateOf("Not paired")
    private val lines = mutableStateListOf<Line>()
    private var channels by mutableStateOf(emptyList<Choice>())
    private var agents by mutableStateOf(emptyList<Choice>())
    private var channel by mutableStateOf<Choice?>(null)
    private var agent by mutableStateOf<Choice?>(null)
    private var screen by mutableStateOf(Screen.Chat)

    // The spoken message so far, and whether it is about to be sent.
    private var heard by mutableStateOf("")
    private var listening by mutableStateOf(ListenState.Listening)
    private var recognizer: SpeechRecognizer? = null
    private var backToCompose = false
    private val micPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) listen()
    }

    // Who is working right now, and until when we believe it without a fresh signal.
    private val working = HashMap<String, Long>()
    private var busy by mutableStateOf<String?>(null)
    private val main = Handler(Looper.getMainLooper())
    private val expireBusy = Runnable(::refreshBusy)

    private var media by mutableStateOf<MediaFetcher?>(null)
    private var viewing by mutableStateOf<String?>(null)

    private var pairing: Pairing? = null
    private var connection: RelayConnection? = null
    private var me: String = ""
    private var subscription: String? = null
    private val shown = HashSet<String>()

    // The phone can pair, or pair again, while this screen is open.
    private val onPaired = SharedPreferences.OnSharedPreferenceChangeListener { _, name ->
        if (name == "key") runOnUiThread(::reconnect)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        SecretStore.prefs(this).registerOnSharedPreferenceChangeListener(onPaired)
        setContent {
            BuzzWatchTheme {
                BackHandler(enabled = screen != Screen.Chat) {
                    stopListening()
                    // Back from an input goes to the input choice; from there, to the conversation.
                    screen = when (screen) {
                        Screen.Listen, Screen.Type, Screen.Emoji -> Screen.Compose
                        else -> Screen.Chat
                    }
                }
                when (screen) {
                    Screen.Chat -> Conversation(
                        status = status,
                        title = channel?.name ?: "Buzz",
                        lines = lines,
                        busy = busy,
                        media = media,
                        onView = {
                            viewing = it
                            screen = Screen.Image
                        },
                        enabled = status == "Connected" && channel != null,
                        onSpeak = { screen = Screen.Compose },
                        onPick = { if (channels.isNotEmpty()) screen = Screen.Channels },
                    )
                    Screen.Channels -> Picker("Channel", channels, channel?.id, media, onBack = { screen = Screen.Chat }) {
                        open(it)
                    }
                    Screen.Agents -> Picker("Talk to", agents, agent?.id, media, onBack = ::afterAgentPicker) {
                        choose(it)
                        afterAgentPicker()
                    }
                    Screen.Compose -> ComposeChoice(
                        agent = agentLabel(),
                        picture = agent?.picture,
                        media = media,
                        canChange = agents.size > 1,
                        onPickAgent = {
                            backToCompose = true
                            screen = Screen.Agents
                        },
                        onEmoji = { screen = Screen.Emoji },
                        onMic = ::speak,
                        onKeyboard = { screen = Screen.Type },
                    )
                    Screen.Listen -> Listen(
                        agent = agentLabel(),
                        picture = agent?.picture,
                        media = media,
                        heard = heard,
                        state = listening,
                        onSend = { deliver(heard) },
                        onRetry = ::listen,
                    )
                    Screen.Type -> Type(agentLabel(), agent?.picture, media, onSend = ::deliver)
                    Screen.Emoji -> EmojiChoice(onPick = ::deliver)
                    Screen.Image -> FullImage(viewing, media) { screen = Screen.Chat }
                }
            }
        }
        reconnect()
    }

    override fun onResume() {
        super.onResume()
        if (connection == null && status == "Disconnected") reconnect()
    }

    override fun onStop() {
        // Never keep the microphone open once the screen is left.
        if (screen == Screen.Listen && listening == ListenState.Listening) {
            stopListening()
            screen = Screen.Compose
        }
        super.onStop()
    }

    override fun onDestroy() {
        main.removeCallbacks(expireBusy)
        SecretStore.prefs(this).unregisterOnSharedPreferenceChangeListener(onPaired)
        io.execute { connection?.close() }
        io.shutdown()
        super.onDestroy()
    }

    private fun reconnect() {
        val paired = SecretStore.load(this) ?: return
        pairing = paired
        status = "Connecting…"
        io.execute {
            connection?.close()
            connection = null
            subscription = null
            try {
                val key = WatchKey.fromHex(paired.secretHex)
                media = MediaFetcher(paired.relayUrl, key)
                val relay = RelayConnection(paired.relayUrl, key, onLost = {
                    runOnUiThread {
                        connection = null
                        status = "Disconnected"
                    }
                })
                relay.connect()
                me = key.pubkey
                connection = relay
                val found = myChannels(relay)
                val stored = SecretStore.prefs(this).getString("channel", null)
                val first = found.firstOrNull { it.id == stored }
                    ?: found.firstOrNull { it.name == "watch" }
                    ?: found.firstOrNull()
                runOnUiThread {
                    channels = found
                    status = "Connected"
                }
                if (first != null) load(relay, first)
            } catch (error: Exception) {
                runOnUiThread { status = "Can't connect: ${error.message ?: error.javaClass.simpleName}" }
            }
        }
    }

    /** The channels this identity is a member of, by name. */
    private fun myChannels(relay: RelayConnection): List<Choice> {
        val ids = relay.query(filter(39002).put("#p", JSONArray(listOf(me))))
            .mapNotNull { it.tag("d") }.distinct()
        if (ids.isEmpty()) return emptyList()
        return relay.query(filter(39000).put("#d", JSONArray(ids)))
            .groupBy { it.tag("d") }
            .mapNotNull { (id, versions) ->
                val name = versions.maxBy { it.createdAt }.tag("name")
                if (id == null || name.isNullOrBlank()) null else Choice(id, name)
            }
            .sortedBy { it.name.lowercase() }
    }

    private fun open(picked: Choice) {
        val relay = connection ?: return
        screen = Screen.Chat
        io.execute { runCatching { load(relay, picked) } }
    }

    /** Switch the conversation to [picked]: its agents, its recent messages, then live ones. */
    private fun load(relay: RelayConnection, picked: Choice) {
        subscription?.let(relay::unsubscribe)
        val members = relay.query(filter(39002).put("#d", JSONArray(listOf(picked.id))).put("limit", 1))
            .maxByOrNull { it.createdAt }?.tags.orEmpty()
            .filter { it.size > 1 && it[0] == "p" && it[1] != me }
        // Agents carry the bot role. A channel that marks none still lets you
        // address whoever else is in it.
        val bots = members.filter { it.getOrNull(2) == "bot" }.ifEmpty { members }.map { it[1] }
        val names = if (bots.isEmpty()) emptyMap<String, Pair<String?, String?>>() else {
            relay.query(filter(0).put("authors", JSONArray(bots)))
                .groupBy { it.pubkey }
                .mapValues { (_, versions) -> profile(versions.maxBy { it.createdAt }) }
        }
        val found = bots
            .map { Choice(it, names[it]?.first ?: (it.take(8) + "…"), names[it]?.second) }
            .sortedBy { it.name.lowercase() }
        val prefs = SecretStore.prefs(this)
        val chosen = found.firstOrNull { it.id == prefs.getString("agent:${picked.id}", null) } ?: found.firstOrNull()
        val history = relay.query(filter(9).put("#h", JSONArray(listOf(picked.id))).put("limit", 10))
            .sortedBy { it.createdAt }
        prefs.edit().putString("channel", picked.id).apply()
        runOnUiThread {
            channel = picked
            agents = found
            agent = chosen
            lines.clear()
            shown.clear()
            working.clear()
            refreshBusy()
            history.forEach(::show)
        }
        subscription = relay.subscribe(picked.id) { event -> runOnUiThread { show(event) } }
    }

    private fun show(event: NostrEvent) {
        if (event.kind == ACTIVITY) {
            // Agents repeat this every few seconds while they work.
            if (event.pubkey != me) {
                working[event.pubkey] = System.currentTimeMillis() + ACTIVITY_TTL_MS
                refreshBusy()
            }
            return
        }
        // A message from someone ends their indicator: the answer has arrived.
        if (working.remove(event.pubkey) != null) refreshBusy()
        if (!shown.add(event.id)) return
        val media = attachments(event)
        // The attachment is shown as a picture, so its address is dropped from the text.
        var text = event.content
        for (item in media) {
            text = text.replace(Regex("!\\[[^\\]]*]\\(" + Regex.escape(item.url) + "\\)"), "").replace(item.url, "")
        }
        lines.add(Line(mine = event.pubkey == me, text = text.trim(), media = media))
    }

    /** Recompute who is working, and keep checking until nobody is. */
    private fun refreshBusy() {
        main.removeCallbacks(expireBusy)
        val now = System.currentTimeMillis()
        working.values.removeAll { it <= now }
        busy = when (working.size) {
            0 -> null
            1 -> (agents.firstOrNull { it.id == working.keys.first() }?.name ?: "Someone") + " is working"
            else -> "${working.size} are working"
        }
        if (working.isNotEmpty()) main.postDelayed(expireBusy, 1000)
    }

    private fun choose(picked: Choice) {
        agent = picked
        channel?.let { SecretStore.prefs(this).edit().putString("agent:${it.id}", picked.id).apply() }
    }

    private fun agentLabel() = agent?.name ?: channel?.name ?: "Buzz"

    private fun afterAgentPicker() {
        screen = if (backToCompose) Screen.Compose else Screen.Chat
        backToCompose = false
    }

    /** Send what was composed and return to the conversation. */
    private fun deliver(text: String) {
        stopListening()
        screen = Screen.Chat
        if (text.isNotBlank()) send(text.trim())
    }

    private fun speak() {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            micPermission.launch(Manifest.permission.RECORD_AUDIO)
        } else {
            listen()
        }
    }

    /** Record a spoken message. Nothing is sent until the owner confirms it. */
    private fun listen() {
        stopListening()
        heard = ""
        screen = Screen.Listen
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            listening = ListenState.Missed
            return
        }
        listening = ListenState.Listening
        recognizer = SpeechRecognizer.createSpeechRecognizer(this).apply {
            setRecognitionListener(object : RecognitionListener {
                override fun onPartialResults(partial: Bundle?) {
                    best(partial)?.let { heard = it }
                }

                override fun onResults(results: Bundle?) {
                    val text = best(results)
                    if (text.isNullOrBlank()) {
                        listening = ListenState.Missed
                    } else {
                        heard = text
                        listening = ListenState.Heard
                    }
                }

                override fun onError(error: Int) {
                    if (listening == ListenState.Listening) {
                        listening = if (heard.isBlank()) ListenState.Missed else ListenState.Heard
                    }
                }

                override fun onReadyForSpeech(params: Bundle?) = Unit
                override fun onBeginningOfSpeech() = Unit
                override fun onRmsChanged(rmsdB: Float) = Unit
                override fun onBufferReceived(buffer: ByteArray?) = Unit
                override fun onEndOfSpeech() = Unit
                override fun onEvent(eventType: Int, params: Bundle?) = Unit
            })
            startListening(
                Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                    .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    .putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true),
            )
        }
    }

    private fun stopListening() {
        recognizer?.destroy()
        recognizer = null
    }

    private fun best(results: Bundle?): String? =
        results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.trim()

    private fun send(text: String) {
        val relay = connection ?: return
        val target = channel ?: return
        // Agents answer only when mentioned, so each message mentions the chosen one.
        val mention = listOfNotNull(agent?.let { listOf("p", it.id) })
        io.execute {
            try {
                val id = relay.sendMessage(target.id, text, mention)
                runOnUiThread { if (shown.add(id)) lines.add(Line(mine = true, text = text)) }
            } catch (error: Exception) {
                runOnUiThread { status = "Not sent: ${error.message ?: error.javaClass.simpleName}" }
            }
        }
    }
}

private fun filter(kind: Int) = JSONObject().put("kinds", JSONArray(listOf(kind)))

private fun NostrEvent.tag(name: String): String? = tags.firstOrNull { it.size > 1 && it[0] == name }?.get(1)

/** A profile's display name and picture address, where it has them. */
private fun profile(profile: NostrEvent): Pair<String?, String?> = runCatching {
    val json = JSONObject(profile.content)
    val name = json.optString("display_name").ifBlank { json.optString("name") }.ifBlank { null }
    name to json.optString("picture").ifBlank { null }
}.getOrDefault(null to null)

private const val ACTIVITY = 20002

// Matches the phone app: an indicator lasts this long without a fresh signal.
private const val ACTIVITY_TTL_MS = 8000L

internal enum class ListenState { Listening, Heard, Missed }
