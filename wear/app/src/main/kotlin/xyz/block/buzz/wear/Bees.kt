package xyz.block.buzz.wear

import android.provider.Settings
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/** Shown while the watch reaches the relay: the Buzz bees, flying. */
@Composable
internal fun Connecting(label: String) {
    Scaffold(timeText = { TimeText() }) {
        BeeSwarm(Modifier.fillMaxSize().clearAndSetSemantics {})
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(label, style = MaterialTheme.typography.title3, color = MaterialTheme.colors.onBackground)
        }
    }
}

// Bee geometry from the phone app's assets/images/welcome-bee.svg (viewBox 466 x 309).
private const val BEE_WIDTH = 466f
private const val BEE_HEIGHT = 309f
private const val BEE =
    "M128 70.3 A91.7 91.7 0 1 0 128 238.7 Z M338 70.3 A91.7 91.7 0 1 1 338 238.7 Z " +
        "M162 0 H304 A34 34 0 0 1 338 34 V275 A34 34 0 0 1 304 309 H162 A34 34 0 0 1 128 275 V34 A34 34 0 0 1 162 0 Z " +
        "M220.3 84.4 A27 27 0 1 1 166.3 84.4 A27 27 0 1 1 220.3 84.4 Z " +
        "M303 84.4 A27 27 0 1 1 249 84.4 A27 27 0 1 1 303 84.4 Z " +
        "M171.3 157.2 H298.2 A5 5 0 0 1 303.2 162.2 V190.5 A5 5 0 0 1 298.2 195.5 H171.3 A5 5 0 0 1 166.3 190.5 V162.2 A5 5 0 0 1 171.3 157.2 Z " +
        "M171.9 235.1 H298.1 A5 5 0 0 1 303.1 240.1 V267.7 A5 5 0 0 1 298.1 272.7 H171.9 A5 5 0 0 1 166.9 267.7 V240.1 A5 5 0 0 1 171.9 235.1 Z"

/** The phone's swarm is tuned for a phone; on a watch everything is drawn at this share of that size. */
private const val WATCH_SCALE = 0.5f
private const val STEP = 1f / 60f

@Composable
private fun BeeSwarm(modifier: Modifier) {
    val context = LocalContext.current
    val still = remember {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
    val bee = remember { PathParser().parsePathString(BEE).toPath().apply { fillType = PathFillType.EvenOdd } }
    val motion = remember { BeeMotion() }
    var frame by remember { mutableLongStateOf(0L) }
    val yellow = MaterialTheme.colors.primary
    val pale = Color(0xFFD7E7F5)

    if (!still) {
        LaunchedEffect(motion) {
            var previous = 0L
            var remainder = 0f
            while (true) {
                withFrameNanos { now ->
                    // A fixed 60 Hz step, as on the phone; never catch up on a long pause.
                    if (previous != 0L) remainder += ((now - previous) / 1e9f).coerceIn(0f, 0.05f)
                    previous = now
                    while (remainder >= STEP) {
                        motion.advance(STEP)
                        remainder -= STEP
                    }
                    frame = now
                }
            }
        }
    }

    Canvas(modifier) {
        frame // Redraw on every simulated frame.
        val unit = density * WATCH_SCALE
        motion.resize(Size(size.width / unit, size.height / unit))
        val arrived = if (still) 1f else 1f - (1f - (motion.elapsed / 1.05f).coerceIn(0f, 1f)).pow(3)
        val drawn = 46f * unit / BEE_WIDTH
        motion.bees.forEachIndexed { index, it ->
            val at = (it.entrance + (it.position - it.entrance) * arrived) * unit
            withTransform({
                translate(at.x, at.y)
                rotate(it.rotation * 180f / PI.toFloat(), pivot = Offset.Zero)
                scale(drawn, drawn, pivot = Offset.Zero)
                translate(-BEE_WIDTH / 2, -BEE_HEIGHT / 2)
            }) { drawPath(bee, if (index % 2 == 1) pale else yellow) }
        }
    }
}

private class Bee(size: Size, index: Int) {
    val seed = ((index + 1) * 0.7548776662 % 1).toFloat()
    private val u = ((0.5 + (index + 1) / 1.324717957244746) % 1).toFloat()
    private val v = ((0.5 + (index + 1) / 1.324717957244746.pow(2)) % 1).toFloat()
    private val bearing = seed * TAU + index * 0.37f
    var position = Offset(u * size.width, v * size.height)
    var velocity = Offset.Zero
    var home = Offset((0.12f + u * 0.76f) * size.width, (0.14f + v * 0.72f) * size.height)
    var entrance = Offset(
        size.width / 2 + cos(bearing) * (size.width * 0.7f + 46f),
        size.height / 2 + sin(bearing) * (size.height * 0.7f + 31f),
    )
    var heading = seed * TAU
    var rotation = seed * TAU + PI.toFloat() / 2
}

private const val TAU = (PI * 2).toFloat()

/**
 * The phone app's welcome-swarm flight model (website_bee_motion.dart):
 * wandering heading, periodic darting, separation, home attraction and soft
 * edge turns. Fewer bees, since the screen is small.
 */
private class BeeMotion {
    var size = Size.Zero
        private set
    var bees = emptyList<Bee>()
        private set
    var elapsed = 0f
        private set

    fun resize(next: Size) {
        if (next == size || next.isEmpty()) return
        if (bees.isEmpty()) {
            bees = List(6) { Bee(next, it) }
        } else {
            fun remap(point: Offset) = Offset(point.x / size.width * next.width, point.y / size.height * next.height)
            for (bee in bees) {
                bee.position = remap(bee.position)
                bee.home = remap(bee.home)
                bee.entrance = remap(bee.entrance)
            }
        }
        size = next
    }

    fun advance(dt: Float) {
        if (bees.isEmpty()) return
        elapsed += dt
        val positions = bees.map { it.position }
        bees.forEachIndexed { index, bee ->
            val p = bee.position
            val seed = bee.seed
            var heading = bee.heading +
                (sin(elapsed * (0.27f + seed * 0.4f) + seed * TAU) + 0.6f * sin(elapsed * (0.13f + seed * 0.11f) + seed * 7)) *
                1.15f * dt
            fun edge(value: Float, extent: Float) = when {
                value < EDGE -> 1 - value / EDGE
                value > extent - EDGE -> -(1 - (extent - value) / EDGE)
                else -> 0f
            }
            val turn = Offset(edge(p.x, size.width), edge(p.y, size.height))
            if (turn != Offset.Zero) {
                val delta = (atan2(turn.y, turn.x) - heading + PI.toFloat() * 3).mod(TAU) - PI.toFloat()
                heading += delta * 3.2f * min(1f, turn.getDistance()) * dt
            }
            val phase = (elapsed * (0.24f + seed * 0.2f) + seed * 5.37f).mod(1f)
            val burst = if (phase < 0.18f) sin(phase / 0.18f * PI.toFloat()) else 0f
            val speed = max(
                58 * 0.46f,
                58 * (1 + sin(elapsed * (0.42f + seed * 0.28f) + seed * TAU) * 0.32f) + max(1f, size.width) * 1.1f * burst,
            )
            val target = Offset(cos(heading), sin(heading)) * speed
            var velocity = bee.velocity + (target - bee.velocity) * ((2.4f + 11 * burst) * dt)
            positions.forEachIndexed { other, position ->
                if (other != index) {
                    val delta = p - position
                    val distance = delta.getDistance()
                    if (distance > 0 && distance < 66) velocity += delta * (1300 * (1 - distance / 66) / distance * dt)
                }
            }
            velocity += (bee.home - p) * (0.18f * dt)
            velocity += turn * (900 * dt)
            velocity *= 0.97f
            var next = p + velocity * dt
            if (next.x < 0 || next.x > size.width) velocity = Offset(-velocity.x * 0.5f, velocity.y)
            if (next.y < 0 || next.y > size.height) velocity = Offset(velocity.x, -velocity.y * 0.5f)
            next = Offset(next.x.coerceIn(0f, size.width), next.y.coerceIn(0f, size.height))
            bee.position = next
            bee.velocity = velocity
            bee.heading = heading
            if (hypot(velocity.x, velocity.y) > 6) {
                val delta = (atan2(velocity.y, velocity.x) + PI.toFloat() / 2 - bee.rotation + PI.toFloat() * 3).mod(TAU) - PI.toFloat()
                bee.rotation += delta * 0.18f
            }
        }
    }

    private companion object {
        /** How near an edge a bee starts turning back; narrower than the phone's 110, for a small screen. */
        const val EDGE = 90f
    }
}
