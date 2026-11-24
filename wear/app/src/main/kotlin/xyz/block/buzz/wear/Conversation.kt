package xyz.block.buzz.wear

import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.State
import androidx.compose.runtime.produceState
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import xyz.block.buzz.wear.core.Attachment
import xyz.block.buzz.wear.core.MediaFetcher
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.Colors
import androidx.wear.compose.material.LocalContentColor
import androidx.wear.compose.material.CompactChip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import androidx.wear.compose.material.scrollAway
import androidx.wear.compose.material.Vignette
import androidx.wear.compose.material.VignettePosition

// Buzz's dark scheme (mobile/lib/shared/theme/color_scheme.dart) with the
// Chartreuse accent. Black is the background: it costs no power on OLED.
private val Chartreuse = Color(0xFFD7D72E)
private val BuzzColors = Colors(
    primary = Chartreuse,
    primaryVariant = Chartreuse,
    secondary = Color(0xFFC7C7C7),
    secondaryVariant = Color(0xFFC7C7C7),
    background = Color(0xFF000000),
    surface = Color(0xFF282828),
    error = Color(0xFFFF9592),
    onPrimary = Color(0xFF000000),
    onSecondary = Color(0xFF000000),
    onBackground = Color(0xFFFFFFFF),
    onSurface = Color(0xFFFFFFFF),
    onSurfaceVariant = Color(0xFFC7C7C7),
    onError = Color(0xFF191111),
)

@Composable
internal fun BuzzWatchTheme(content: @Composable () -> Unit) =
    MaterialTheme(colors = BuzzColors, content = content)

@Composable
internal fun Conversation(
    status: String,
    title: String,
    lines: List<Line>,
    busy: String?,
    media: MediaFetcher?,
    onView: (String) -> Unit,
    enabled: Boolean,
    onSpeak: () -> Unit,
    onPick: () -> Unit,
) {
    val list = rememberScalingLazyListState()
    // A round screen is narrowest at its top and bottom, so text keeps clear
    // of the edge by a share of the width, not a fixed margin.
    val inset = (LocalConfiguration.current.screenWidthDp * if (LocalConfiguration.current.isScreenRound) 0.1f else 0.04f).dp
    val connected = status == "Connected"

    // Keep the newest message in view.
    LaunchedEffect(lines.size, busy != null) {
        if (lines.isNotEmpty()) list.animateScrollToItem(lines.size - if (busy != null) 0 else 1)
    }

    Scaffold(
        timeText = { TimeText() },
        positionIndicator = { PositionIndicator(scalingLazyListState = list) },
    ) {
        ScalingLazyColumn(
            state = list,
            modifier = Modifier.fillMaxSize(),
            // Room for the pinned header above and the pinned Speak button below.
            contentPadding = PaddingValues(top = 62.dp, bottom = 72.dp),
            autoCentering = null,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            if (lines.isEmpty()) {
                item {
                    Text(
                        text = when {
                            status == "Not paired" -> "On your phone, open Buzz, then Settings, then Pair watch"
                            else -> "Ask your agent"
                        },
                        style = MaterialTheme.typography.body2,
                        color = MaterialTheme.colors.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().padding(horizontal = inset, vertical = 4.dp),
                    )
                }
            }
            items(lines) { line -> Bubble(line, inset, media, onView) }
            if (busy != null) {
                item {
                    Text(
                        text = "$busy…",
                        style = MaterialTheme.typography.caption1,
                        color = MaterialTheme.colors.primary,
                        modifier = Modifier.fillMaxWidth().padding(horizontal = inset + 6.dp),
                    )
                }
            }
        }

        // Pinned: where you are and who you are talking to. Tap to change.
        // Messages fade out beneath it rather than running under the text.
        Box(
            contentAlignment = Alignment.BottomCenter,
            modifier = Modifier.fillMaxWidth().height(58.dp).background(
                Brush.verticalGradient(0.75f to MaterialTheme.colors.background, 1f to Color.Transparent),
            ),
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .padding(bottom = 6.dp)
                    .widthIn(max = 150.dp)
                    .background(MaterialTheme.colors.surface, CircleShape)
                    .clickable(onClickLabel = "Change channel", onClick = onPick)
                    .padding(horizontal = 10.dp, vertical = 4.dp)
                    .semantics(mergeDescendants = true) { contentDescription = "$title. $status" },
            ) {
                Box(
                    Modifier.size(6.dp).background(
                        if (connected) MaterialTheme.colors.primary else MaterialTheme.colors.onSurfaceVariant,
                        CircleShape,
                    ),
                )
                Text(
                    text = if (connected) title else status,
                    style = MaterialTheme.typography.caption2,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colors.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(start = 6.dp),
                )
            }
        }

        // Pinned: Speak is always one tap away, however long the conversation.
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier.fillMaxSize().wrapContentHeight(Alignment.Bottom).fillMaxWidth().height(70.dp).background(
                Brush.verticalGradient(0f to Color.Transparent, 0.3f to MaterialTheme.colors.background),
            ),
        ) {
            Button(
                onClick = onSpeak,
                enabled = enabled,
                colors = ButtonDefaults.primaryButtonColors(),
                modifier = Modifier.size(48.dp).semantics { contentDescription = "Speak a message" },
            ) { MicGlyph(LocalContentColor.current) }
        }
    }
}

/** A round profile picture, or nothing while it loads or where there is none. */
@Composable
private fun Avatar(picture: String?, media: MediaFetcher?, size: androidx.compose.ui.unit.Dp) {
    val loaded by rememberPicture(picture, media, maxSide = 96)
    loaded?.let {
        Image(
            bitmap = it,
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.size(size).clip(CircleShape),
        )
    }
}

/** The agent a message will go to, pinned under the clock. Tap to change when there is a choice. */
@Composable
private fun AgentPill(agent: String, picture: String?, media: MediaFetcher?, canChange: Boolean, onPick: () -> Unit) {
    Box(Modifier.fillMaxWidth().height(62.dp), contentAlignment = Alignment.BottomCenter) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier
                .padding(bottom = 6.dp)
                .widthIn(max = 150.dp)
                .background(MaterialTheme.colors.surface, CircleShape)
                .clickable(enabled = canChange, onClickLabel = "Change agent", onClick = onPick)
                .padding(start = 4.dp, end = 10.dp, top = 3.dp, bottom = 3.dp)
                .semantics(mergeDescendants = true) { contentDescription = "To $agent" },
        ) {
            Avatar(picture, media, 22.dp)
            Text(
                text = if (canChange) "$agent ▾" else agent,
                style = MaterialTheme.typography.caption2,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colors.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(start = 2.dp),
            )
        }
    }
}

/** A way back that does not depend on knowing the swipe gesture. */
@Composable
private fun BackChip(label: String, onBack: () -> Unit) = CompactChip(
    label = { Text(label) },
    onClick = onBack,
    colors = ChipDefaults.chipColors(
        backgroundColor = MaterialTheme.colors.surface,
        contentColor = MaterialTheme.colors.onSurface,
    ),
)

/** The bottom of an input screen: its actions, centred where a round screen is widest. */
@Composable
private fun BottomActions(content: @Composable () -> Unit) = Row(
    horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
    verticalAlignment = Alignment.CenterVertically,
    modifier = Modifier.fillMaxSize().wrapContentHeight(Alignment.Bottom).fillMaxWidth().padding(bottom = 12.dp),
) { content() }

/** How to write the message: emoji, voice or keyboard. */
@Composable
internal fun ComposeChoice(
    agent: String,
    picture: String?,
    media: MediaFetcher?,
    canChange: Boolean,
    onPickAgent: () -> Unit,
    onEmoji: () -> Unit,
    onMic: () -> Unit,
    onKeyboard: () -> Unit,
    onBack: () -> Unit,
) {
    Scaffold(timeText = { TimeText() }) {
        AgentPill(agent, picture, media, canChange, onPickAgent)
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxSize(),
        ) {
            Button(
                onClick = onEmoji,
                colors = ButtonDefaults.secondaryButtonColors(),
                modifier = Modifier.size(52.dp).semantics { contentDescription = "Emoji" },
            ) { Text("☺", style = MaterialTheme.typography.title1) }
            Button(
                onClick = onMic,
                colors = ButtonDefaults.primaryButtonColors(),
                modifier = Modifier.size(60.dp).semantics { contentDescription = "Speak" },
            ) { MicGlyph(LocalContentColor.current) }
            Button(
                onClick = onKeyboard,
                colors = ButtonDefaults.secondaryButtonColors(),
                modifier = Modifier.size(52.dp).semantics { contentDescription = "Keyboard" },
            ) { Text("⌨", style = MaterialTheme.typography.title1) }
        }
        BottomActions { BackChip("Back", onBack) }
    }
}

/** Recording a spoken message, then one button to confirm it. */
@Composable
internal fun Listen(
    agent: String,
    picture: String?,
    media: MediaFetcher?,
    heard: String,
    state: ListenState,
    onSend: () -> Unit,
    onRetry: () -> Unit,
    onBack: () -> Unit,
) {
    val inset = (LocalConfiguration.current.screenWidthDp * 0.12f).dp
    Scaffold(timeText = { TimeText() }) {
        AgentPill(agent, picture, media, canChange = false, onPick = {})
        Box(Modifier.fillMaxSize().padding(horizontal = inset), contentAlignment = Alignment.Center) {
            Text(
                text = when {
                    heard.isNotEmpty() -> heard
                    state == ListenState.Missed -> "Didn't catch that"
                    else -> "Listening…"
                },
                style = MaterialTheme.typography.body1,
                color = if (heard.isEmpty()) MaterialTheme.colors.onSurfaceVariant else MaterialTheme.colors.onBackground,
                textAlign = TextAlign.Center,
                maxLines = 4,
                overflow = TextOverflow.Ellipsis,
            )
        }
        BottomActions {
            when (state) {
                ListenState.Heard -> {
                    BackChip("Cancel", onBack)
                    SendButton(onSend)
                }
                ListenState.Missed -> {
                    BackChip("Back", onBack)
                    BackChip("Try again", onRetry)
                }
                ListenState.Listening -> BackChip("Cancel", onBack)
            }
        }
    }
}

@Composable
private fun SendButton(onSend: () -> Unit) = Button(
    onClick = onSend,
    colors = ButtonDefaults.primaryButtonColors(),
    modifier = Modifier.size(48.dp).semantics { contentDescription = "Send" },
) { Text("✓", style = MaterialTheme.typography.title2, fontWeight = FontWeight.Bold) }

/** Typing a message: the watch keyboard opens at once, then one button to confirm. */
@Composable
internal fun Type(
    agent: String,
    picture: String?,
    media: MediaFetcher?,
    onSend: (String) -> Unit,
    onBack: () -> Unit,
) {
    var text by remember { mutableStateOf("") }
    val focus = remember { FocusRequester() }
    val inset = (LocalConfiguration.current.screenWidthDp * 0.12f).dp
    LaunchedEffect(Unit) { focus.requestFocus() }
    Scaffold(timeText = { TimeText() }) {
        AgentPill(agent, picture, media, canChange = false, onPick = {})
        Box(Modifier.fillMaxSize().padding(horizontal = inset), contentAlignment = Alignment.Center) {
            BasicTextField(
                value = text,
                onValueChange = { text = it },
                textStyle = MaterialTheme.typography.body1.copy(
                    color = MaterialTheme.colors.onBackground,
                    textAlign = TextAlign.Center,
                ),
                cursorBrush = SolidColor(MaterialTheme.colors.primary),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                maxLines = 4,
                modifier = Modifier.fillMaxWidth().focusRequester(focus),
                decorationBox = { field ->
                    if (text.isEmpty()) {
                        Text(
                            "Tap to type",
                            color = MaterialTheme.colors.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                    field()
                },
            )
        }
        BottomActions {
            BackChip(if (text.isBlank()) "Back" else "Cancel", onBack)
            if (text.isNotBlank()) SendButton { onSend(text) }
        }
    }
}

private val emojis = listOf("👍", "👎", "🙏", "😂", "❤️", "🎉", "👀", "🤔", "✅", "❌", "🔥", "😅")

/** A few emoji; a tap sends it. */
@Composable
internal fun EmojiChoice(onPick: (String) -> Unit, onBack: () -> Unit) {
    val list = rememberScalingLazyListState()
    Scaffold(positionIndicator = { PositionIndicator(scalingLazyListState = list) }) {
        ScalingLazyColumn(state = list, modifier = Modifier.fillMaxWidth()) {
            items(emojis.chunked(3)) { row ->
                Row(
                    horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    for (emoji in row) {
                        Button(
                            onClick = { onPick(emoji) },
                            colors = ButtonDefaults.secondaryButtonColors(),
                            modifier = Modifier.size(48.dp),
                        ) { Text(emoji, style = MaterialTheme.typography.title2) }
                    }
                }
            }
            item { BackChip("Back", onBack) }
        }
    }
}

/** A full-screen list to choose one of [options]; the current one is highlighted. */
@Composable
internal fun Picker(
    title: String,
    options: List<Choice>,
    selected: String?,
    media: MediaFetcher?,
    onBack: () -> Unit,
    onPick: (Choice) -> Unit,
) {
    val list = rememberScalingLazyListState()
    Scaffold(
        vignette = { Vignette(vignettePosition = VignettePosition.TopAndBottom) },
        positionIndicator = { PositionIndicator(scalingLazyListState = list) },
    ) {
        ScalingLazyColumn(state = list, modifier = Modifier.fillMaxWidth()) {
            item {
                Text(
                    text = title,
                    style = MaterialTheme.typography.caption1,
                    color = MaterialTheme.colors.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            items(options) { option ->
                Chip(
                    label = { Text(option.name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                    icon = if (option.picture == null) null else ({ Avatar(option.picture, media, 24.dp) }),
                    onClick = { onPick(option) },
                    colors = if (option.id == selected) ChipDefaults.primaryChipColors() else ChipDefaults.secondaryChipColors(),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            item {
                CompactChip(
                    label = { Text("Back") },
                    onClick = onBack,
                    colors = ChipDefaults.chipColors(
                        backgroundColor = MaterialTheme.colors.surface,
                        contentColor = MaterialTheme.colors.onSurface,
                    ),
                )
            }
        }
    }
}

/** A microphone drawn in place, to avoid an icon library for one glyph. */
@Composable
private fun MicGlyph(color: Color) = Canvas(Modifier.size(20.dp)) {
    val w = size.width
    val stroke = w * 0.09f
    drawRoundRect(
        color = color,
        topLeft = Offset(w * 0.37f, w * 0.08f),
        size = Size(w * 0.26f, w * 0.5f),
        cornerRadius = CornerRadius(w * 0.13f),
    )
    drawArc(
        color = color,
        startAngle = 0f,
        sweepAngle = 180f,
        useCenter = false,
        topLeft = Offset(w * 0.22f, w * 0.2f),
        size = Size(w * 0.56f, w * 0.52f),
        style = Stroke(stroke, cap = StrokeCap.Round),
    )
    drawLine(color, Offset(w * 0.5f, w * 0.72f), Offset(w * 0.5f, w * 0.9f), stroke, StrokeCap.Round)
}

@Composable
private fun Bubble(line: Line, inset: androidx.compose.ui.unit.Dp, media: MediaFetcher?, onView: (String) -> Unit) {
    Row(
        horizontalArrangement = if (line.mine) Arrangement.End else Arrangement.Start,
        modifier = Modifier.fillMaxWidth().padding(horizontal = inset),
    ) {
        Column(
            verticalArrangement = Arrangement.spacedBy(4.dp),
            horizontalAlignment = if (line.mine) Alignment.End else Alignment.Start,
        ) {
            for (item in line.media) Thumbnail(item, media, onView)
            if (line.text.isNotEmpty()) {
                Text(
                    text = remember(line.text) { markdown(line.text) },
                    style = MaterialTheme.typography.body2,
                    color = if (line.mine) MaterialTheme.colors.onPrimary else MaterialTheme.colors.onSurface,
                    modifier = Modifier
                        .background(
                            if (line.mine) MaterialTheme.colors.primary else MaterialTheme.colors.surface,
                            RoundedCornerShape(16.dp),
                        )
                        .padding(horizontal = 10.dp, vertical = 6.dp)
                        .semantics(mergeDescendants = true) {
                            contentDescription = (if (line.mine) "You: " else "Agent: ") + line.text
                        },
                )
            }
        }
    }
}

/** Loads [url] off the main thread, scaled down to what a watch can show. */
@Composable
private fun rememberPicture(url: String?, media: MediaFetcher?, maxSide: Int): State<ImageBitmap?> =
    produceState<ImageBitmap?>(initialValue = null, url, media) {
        value = if (url == null || media == null) null else withContext(Dispatchers.IO) {
            pictures.get(url) ?: media.fetch(url)?.let { decode(it, maxSide) }?.also { pictures.put(url, it) }
        }
    }

// A few recent pictures, so scrolling back does not download them again.
private val pictures = object : LruCache<String, ImageBitmap>(16 * 1024 * 1024) {
    override fun sizeOf(key: String, value: ImageBitmap) = value.width * value.height * 4
}

private fun decode(bytes: ByteArray, maxSide: Int): ImageBitmap? {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
    var sample = 1
    while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxSide) sample *= 2
    return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
        ?.asImageBitmap()
}

/** A picture in the conversation, or a video's preview frame with its length. */
@Composable
private fun Thumbnail(item: Attachment, media: MediaFetcher?, onView: (String) -> Unit) {
    val picture by rememberPicture(item.preview, media, maxSide = 320)
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(width = 120.dp, height = 90.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colors.surface)
            // A video is for the phone; the watch shows only that one arrived.
            .clickable(enabled = !item.video, onClickLabel = "View picture") { onView(item.url) }
            .semantics { contentDescription = if (item.video) "Video" else "Picture" },
    ) {
        picture?.let {
            Image(bitmap = it, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        }
        if (item.video) {
            val length = item.durationSeconds?.let { "  %d:%02d".format(it / 60, it % 60) }.orEmpty()
            Text(
                text = "▶$length",
                style = MaterialTheme.typography.caption1,
                color = Color.White,
                modifier = Modifier
                    .background(Color.Black.copy(alpha = 0.6f), CircleShape)
                    .padding(horizontal = 8.dp, vertical = 3.dp),
            )
        }
    }
}

/** One picture, as large as the screen allows. Tap to go back. */
@Composable
internal fun FullImage(url: String?, media: MediaFetcher?, onClose: () -> Unit) {
    val picture by rememberPicture(url, media, maxSide = 1024)
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier.fillMaxSize().background(Color.Black).clickable(onClickLabel = "Close", onClick = onClose),
    ) {
        val shown = picture
        if (shown == null) {
            Text("Loading…", color = MaterialTheme.colors.onSurfaceVariant)
        } else {
            Image(bitmap = shown, contentDescription = "Picture", contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize())
        }
    }
}
