package xyz.block.buzz.wear

import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.LocalContentColor
import androidx.wear.compose.material.Text

/**
 * The same Tabler artwork the phone app uses (its `BuzzIcons`).
 *
 * `res/font/tabler_icons.ttf` holds only these glyphs, cut from the phone's
 * `assets/fonts/TablerIcons.ttf`; the README says how to add one.
 */
internal enum class BuzzIcon(val glyph: String) {
    Back(""), // chevron-left
    Close(""), // x
    Check(""), // check
    Mic(""), // microphone
    Smile(""), // mood-smile
    Keyboard(""), // keyboard
    Retry(""), // rotate
    ChevronDown(""), // chevron-down
}

private val tabler = FontFamily(Font(R.font.tabler_icons))

@Composable
internal fun Glyph(icon: BuzzIcon, size: Dp = 22.dp, color: Color = LocalContentColor.current) = Text(
    text = icon.glyph,
    fontFamily = tabler,
    fontSize = size.value.sp,
    lineHeight = size.value.sp,
    color = color,
)

/** A round button that is only an icon; [description] is what a screen reader says. */
@Composable
internal fun IconAction(
    icon: BuzzIcon,
    description: String,
    onClick: () -> Unit,
    primary: Boolean = false,
    enabled: Boolean = true,
    size: Dp = 44.dp,
) = Button(
    onClick = onClick,
    enabled = enabled,
    colors = if (primary) ButtonDefaults.primaryButtonColors() else ButtonDefaults.secondaryButtonColors(),
    modifier = Modifier.size(size).semantics { contentDescription = description },
) { Glyph(icon, size = size * 0.46f) }
