package xyz.block.buzz.wear

import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle

private val Bold = SpanStyle(fontWeight = FontWeight.Bold)
private val Italic = SpanStyle(fontStyle = FontStyle.Italic)
private val Code = SpanStyle(fontFamily = FontFamily.Monospace)
private val Strike = SpanStyle(textDecoration = TextDecoration.LineThrough)

/**
 * The Markdown agents actually write, styled for a small screen: emphasis,
 * code, headings, lists, quotes and links. Links show their text only, since
 * there is nowhere useful to open them on a watch. Anything unrecognised is
 * shown as written.
 */
internal fun markdown(text: String): AnnotatedString = buildAnnotatedString {
    var fenced = false
    var first = true
    for (line in text.lines()) {
        if (line.trimStart().startsWith("```")) {
            fenced = !fenced
            continue
        }
        if (!first) append('\n')
        first = false
        if (fenced) {
            withStyle(Code) { append(line) }
            continue
        }
        val trimmed = line.trimStart()
        val indent = " ".repeat((line.length - trimmed.length) / 2)
        val heading = Regex("^#{1,6}\\s+(.*)$").find(trimmed)
        val bullet = Regex("^[-*+]\\s+(.*)$").find(trimmed)
        when {
            heading != null -> withStyle(Bold) { inline(heading.groupValues[1]) }
            bullet != null -> {
                append("$indent• ")
                inline(bullet.groupValues[1])
            }
            trimmed.startsWith("> ") -> withStyle(Italic) { inline(trimmed.removePrefix("> ")) }
            else -> {
                append(indent)
                inline(trimmed)
            }
        }
    }
}

// Longest markers first, so ** is not read as two *.
private val marks = listOf("**" to Bold, "__" to Bold, "~~" to Strike, "*" to Italic, "_" to Italic)
private val link = Regex("^\\[([^\\]]+)]\\(([^)\\s]+)\\)")

private fun AnnotatedString.Builder.inline(text: String) {
    var i = 0
    scan@ while (i < text.length) {
        if (text[i] == '`') {
            val end = text.indexOf('`', i + 1)
            if (end > i + 1) {
                withStyle(Code) { append(text.substring(i + 1, end)) }
                i = end + 1
                continue
            }
        }
        // A backslash makes the next mark literal, as in snake\_case.
        if (text[i] == '\\' && i + 1 < text.length && !text[i + 1].isLetterOrDigit() && !text[i + 1].isWhitespace()) {
            append(text[i + 1])
            i += 2
            continue
        }
        // An inline picture is shown as an attachment, not as text.
        if (text[i] == '!' && text.getOrNull(i + 1) == '[') {
            val found = link.find(text.substring(i + 1))
            if (found != null) {
                i += 1 + found.value.length
                continue
            }
        }
        if (text[i] == '[') {
            val found = link.find(text.substring(i))
            if (found != null) {
                inline(found.groupValues[1])
                i += found.value.length
                continue
            }
        }
        for ((mark, style) in marks) {
            if (!text.startsWith(mark, i)) continue
            val start = i + mark.length
            val end = text.indexOf(mark, start)
            // An opening mark hugs its text; `_` inside a word (snake_case) is not emphasis.
            val opens = end > start && !text[start].isWhitespace() && !text[end - 1].isWhitespace()
            val inWord = mark == "_" && (text.getOrNull(i - 1)?.isLetterOrDigit() == true ||
                text.getOrNull(end + 1)?.isLetterOrDigit() == true)
            if (opens && !inWord) {
                withStyle(style) { inline(text.substring(start, end)) }
                i = end + mark.length
                continue@scan
            }
        }
        append(text[i])
        i++
    }
}
