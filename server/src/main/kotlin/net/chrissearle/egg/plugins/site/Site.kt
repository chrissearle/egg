package net.chrissearle.egg.plugins.site

import kotlinx.html.FlowContent
import kotlinx.html.HTML
import kotlinx.html.HTMLTag
import kotlinx.html.SPAN
import kotlinx.html.a
import kotlinx.html.body
import kotlinx.html.div
import kotlinx.html.head
import kotlinx.html.i
import kotlinx.html.img
import kotlinx.html.lang
import kotlinx.html.link
import kotlinx.html.main
import kotlinx.html.meta
import kotlinx.html.span
import kotlinx.html.title

/** The first codepoint the sheet covers, and how many it holds. */
private const val FIRST_CODEPOINT = 0x20
private const val GLYPH_COUNT = 95
private const val SPACE_INDEX = 0

/**
 * Writes a string in the game's own lettering.
 *
 * Every character becomes an element masked to its cell of the sprite sheet and
 * filled with the ink colour — the same trick `Message` uses when it tints a
 * glyph PNG at draw time, which is why the result is pixel-identical to the
 * game rather than merely similar.
 *
 * The glyphs are decorative markup, so the whole run carries an `aria-label`
 * with the real text and the individual cells are hidden. Without that the page
 * would be silent to a screen reader.
 *
 * A character outside the font's 0x20-0x7e range is drawn as a space; the BBC's
 * font has nothing else, and the server already refuses to store such a name.
 */
fun FlowContent.pixelText(
    text: String,
    ink: Ink = Ink.GREEN,
    half: Boolean = false,
    wrap: Boolean = false
) {
    val classes =
        listOfNotNull(
            "t",
            if (half) "half" else null,
            if (wrap) "wrap" else null,
            ink.css
        ).joinToString(" ")

    span(classes) {
        attributes["aria-label"] = text
        attributes["role"] = "text"
        if (wrap) wrapped(text) else text.forEach { glyph(it) }
    }
}

/**
 * Glyphs are inline-blocks with no whitespace between them, so a run of them
 * offers the browser nowhere to break and will happily overflow a narrow
 * screen. Grouping each word and putting a real space between the groups gives
 * it break opportunities at word boundaries.
 *
 * Not the default, because a score row's alignment *is* its spaces: letting one
 * wrap would fold the columns. Those rows scroll inside `.board` instead.
 */
private fun SPAN.wrapped(text: String) {
    text.split(" ").forEachIndexed { index, word ->
        if (index > 0) +" "
        span("w") {
            attributes["aria-hidden"] = "true"
            word.forEach { glyph(it) }
        }
    }
}

private fun FlowContent.glyph(character: Char) {
    val index = character.code - FIRST_CODEPOINT
    i {
        attributes["aria-hidden"] = "true"
        style = "--i:${if (index in 0 until GLYPH_COUNT) index else SPACE_INDEX}"
    }
}

/** The letters of the logo, and their x offsets, straight from `Banner`. */
private val LOGO_LETTERS = listOf("C", "H", "U", "C", "K", "I", "E", "E", "G", "G")
private val LOGO_COLUMNS = listOf(0x02, 0x11, 0x20, 0x2F, 0x3E, 0x4D, 0x5C, 0x72, 0x81, 0x90)

/**
 * The real CHUCKIE EGG logo, composed from the ROM letter sprites.
 *
 * `Banner` draws each letter at `COLUMNS[i] * 2` in square pixels; the same
 * doubling is applied here, so the spacing — including the wider gap before
 * EGG — is the original's rather than something eyeballed.
 *
 * How big it gets is CSS's business, not this function's: `--logo-scale` steps
 * with the viewport, and pinning it here in the markup would beat the media
 * query and overflow the page on anything narrow.
 */
fun FlowContent.logo() {
    div("logo") {
        attributes["role"] = "img"
        attributes["aria-label"] = "Chuckie Egg"
        LOGO_LETTERS.forEachIndexed { index, letter ->
            img(alt = "", src = "/assets/banner/$letter.png") {
                style = "left:calc(${LOGO_COLUMNS[index] * 2}px * var(--logo-scale))"
                attributes["aria-hidden"] = "true"
            }
        }
    }
}

/** Where the site's pages link to each other and to the source. */
const val SOURCE_URL = "https://github.com/chrissearle/egg"

/** The shared page shell: palette, font sheet, and the site's own furniture. */
fun HTML.page(
    pageTitle: String,
    block: FlowContent.() -> Unit
) {
    lang = "en"
    head {
        meta(charset = "utf-8")
        meta(name = "viewport", content = "width=device-width, initial-scale=1")
        title(pageTitle)
        link(rel = "stylesheet", href = "/static/style.css")
        link(rel = "icon", href = "/assets/banner/E.png")
    }
    body {
        main {
            block()
        }
    }
}

/** A link styled as a button. `primary` is the one the page wants you to take. */
fun FlowContent.buttonLink(
    href: String,
    label: String,
    primary: Boolean = false
) {
    a(href = href, classes = if (primary) "button primary" else "button") { +label }
}

/** kotlinx.html has no `style` attribute on arbitrary tags by default. */
private var HTMLTag.style: String
    get() = attributes["style"].orEmpty()
    set(value) {
        attributes["style"] = value
    }
